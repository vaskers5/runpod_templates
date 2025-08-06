#!/usr/bin/env bash
set -euo pipefail

# ── Environment ────────────────────────────────────────────────────────────────
BUCKET="${S3_BUCKET:-}"                 # e.g. my-bucket
DATA_DIR="${S3_SYNC_DIR:-/data}"        # local dir to keep in sync
ACCESS_KEY="${S3__ACCESS_KEY:-}"
SECRET_KEY="${S3__SECRET_KEY:-}"
ENDPOINT="${S3__ENDPOINT_URL:-}"        # e.g. https://s3.example.com
LOG_FILE="/var/log/s3_sync.log"
CPU_COUNT="$(nproc)"

# ── Guard rails ────────────────────────────────────────────────────────────────
if [[ -z "$BUCKET" || -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$ENDPOINT" ]]; then
  echo "Missing required S3_* environment variables." >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" "$DATA_DIR"

# ── Ensure rclone is available ────────────────────────────────────────────────
if ! command -v rclone >/dev/null 2>&1; then
  apt-get update && \
  apt-get install -y --no-install-recommends rclone && \
  rm -rf /var/lib/apt/lists/*
fi

# Create a minimal rclone config that relies on env auth
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
[s3]
type = s3
provider = Minio
env_auth = true
endpoint = ${ENDPOINT}
EOF

# ── One-time pull from S3 → local ──────────────────────────────────────────────
echo "$(date '+%F %T') Starting initial pull from s3://$BUCKET to $DATA_DIR" | tee -a "$LOG_FILE"
AWS_ACCESS_KEY_ID="$ACCESS_KEY" \
AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
AWS_EC2_METADATA_DISABLED=true \
rclone sync "s3:$BUCKET" "$DATA_DIR" \
  --s3-endpoint "$ENDPOINT" \
  --stats=1s --stats-one-line --stats-log-level NOTICE \
  --buffer-size=64M --s3-chunk-size=64M \
  --s3-upload-concurrency="$CPU_COUNT" \
  --transfers="$CPU_COUNT" --checkers="$CPU_COUNT" | tee -a "$LOG_FILE"
echo "$(date '+%F %T') Initial pull complete" | tee -a "$LOG_FILE"

# ── Install & start cron, schedule push job ────────────────────────────────────
if ! command -v cron >/dev/null 2>&1; then
  apt-get update && \
  apt-get install -y --no-install-recommends cron && \
  rm -rf /var/lib/apt/lists/*
fi

cat > /etc/cron.d/s3_push <<EOF
# Push local changes back to S3 every 12 hours (at 00 and 12)
0 */12 * * * root \
  AWS_ACCESS_KEY_ID=$ACCESS_KEY \
  AWS_SECRET_ACCESS_KEY=$SECRET_KEY \
  AWS_EC2_METADATA_DISABLED=true \
  rclone sync "$DATA_DIR" "s3:$BUCKET" \
    --s3-endpoint "$ENDPOINT" \
    --stats=1s --stats-one-line --stats-log-level NOTICE \
    --buffer-size=64M --s3-chunk-size=64M \
    --s3-upload-concurrency=$CPU_COUNT \
    --transfers=$CPU_COUNT --checkers=$CPU_COUNT >> $LOG_FILE 2>&1
EOF

chmod 644 /etc/cron.d/s3_push
service cron start >/dev/null 2>&1 || true
echo "$(date '+%F %T') Cron job installed; sync setup complete" | tee -a "$LOG_FILE"
