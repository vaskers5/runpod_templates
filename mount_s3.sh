#!/usr/bin/env bash
set -euo pipefail

BUCKET="${S3_BUCKET:-}"   # required bucket name
MOUNT_POINT="${S3_MOUNT_POINT:-/mnt/s3}"
ACCESS_KEY="${S3__ACCESS_KEY:-}"
SECRET_KEY="${S3__SECRET_KEY:-}"
ENDPOINT="${S3__ENDPOINT_URL:-}"
LOG_FILE="/var/log/s3_sync.log"
CPU_COUNT="$(nproc)"

# install tools for fallback syncing
ensure_sync_tools() {
  if ! command -v rclone >/dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends rclone && rm -rf /var/lib/apt/lists/*
  fi
  # create basic rclone config so the "s3" remote works
  mkdir -p /root/.config/rclone
  cat <<EOF >/root/.config/rclone/rclone.conf
[s3]
type = s3
provider = Minio
env_auth = true
endpoint = ${ENDPOINT}
EOF
  if ! command -v s5cmd >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
      apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*
    fi
    curl -fsSL -o /tmp/s5cmd.tar.gz https://github.com/peak/s5cmd/releases/download/v2.2.2/s5cmd_2.2.2_Linux-64bit.tar.gz \
      && tar -xzf /tmp/s5cmd.tar.gz -C /tmp \
      && install -m 0755 /tmp/s5cmd /usr/local/bin/s5cmd \
      && rm -f /tmp/s5cmd.tar.gz
  fi
  if ! command -v rclone >/dev/null 2>&1 && ! command -v s5cmd >/dev/null 2>&1; then
    if ! aws --version >/dev/null 2>&1; then
      if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        apt-get update && apt-get install -y --no-install-recommends python3-pip && rm -rf /var/lib/apt/lists/*
      fi
      python3 -m pip install -q --no-cache-dir awscli
      if command -v pyenv >/dev/null 2>&1; then
        pyenv rehash
      fi
    fi
  fi
}

# sync files as a fallback when FUSE mounting is unavailable or fails
perform_sync() {
  ensure_sync_tools
  mkdir -p "$MOUNT_POINT"
  echo "$(date '+%F %T') Starting sync from s3://$BUCKET to $MOUNT_POINT" | tee -a "$LOG_FILE"
  if command -v rclone >/dev/null 2>&1; then
    echo "$(date '+%F %T') syncing via rclone" | tee -a "$LOG_FILE"
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
      AWS_EC2_METADATA_DISABLED=true \
      rclone copy "s3:$BUCKET" "$MOUNT_POINT" --s3-endpoint "$ENDPOINT" \
        --stats=1s --stats-one-line --stats-log-level NOTICE \
        --buffer-size=64M --s3-chunk-size=64M \
        --s3-upload-concurrency="$CPU_COUNT" \
        --transfers="$CPU_COUNT" --checkers="$CPU_COUNT" | tee -a "$LOG_FILE"
  elif command -v s5cmd >/dev/null 2>&1; then
    echo "$(date '+%F %T') syncing via s5cmd" | tee -a "$LOG_FILE"
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
      AWS_EC2_METADATA_DISABLED=true \
      s5cmd --stat --endpoint-url "$ENDPOINT" \
        sync --concurrency "$CPU_COUNT" "s3://$BUCKET/*" "$MOUNT_POINT/" | tee -a "$LOG_FILE"
  else
    echo "$(date '+%F %T') syncing via aws s3 sync" | tee -a "$LOG_FILE"
    AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
      AWS_EC2_METADATA_DISABLED=true AWS_MAX_CONCURRENCY="$CPU_COUNT" \
      aws s3 sync "s3://$BUCKET" "$MOUNT_POINT" --endpoint-url "$ENDPOINT" | tee -a "$LOG_FILE"
  fi
  echo "$(date '+%F %T') Sync complete" | tee -a "$LOG_FILE"
}

if [[ -z "$BUCKET" || -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$ENDPOINT" ]]; then
  echo "S3 mount variables not fully specified. Skipping mount."
  exit 0
fi

# ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# ensure s3fs is available
if ! command -v s3fs >/dev/null 2>&1; then
  apt-get update && apt-get install -y --no-install-recommends s3fs && rm -rf /var/lib/apt/lists/*
fi

# check that FUSE device exists and try to load module if missing
if [[ ! -e /dev/fuse ]]; then
  if command -v modprobe >/dev/null 2>&1; then
    modprobe fuse 2>/dev/null || true
  fi
  [[ -e /dev/fuse ]] || { mknod -m 666 /dev/fuse c 10 229 2>/dev/null || true; }
fi

if [[ ! -e /dev/fuse ]]; then
  echo "FUSE device /dev/fuse not found. Falling back to sync." >&2
  echo "$(date '+%F %T') FUSE unavailable; performing S3 sync" | tee -a "$LOG_FILE"
  ensure_sync_tools
  perform_sync
  exit 0
fi

# credentials file for s3fs
echo "$ACCESS_KEY:$SECRET_KEY" > /etc/passwd-s3fs
chmod 600 /etc/passwd-s3fs

mkdir -p "$MOUNT_POINT"

# mount if not already mounted
if mountpoint -q "$MOUNT_POINT"; then
  echo "S3 already mounted at $MOUNT_POINT"
else
  s3fs "$BUCKET" "$MOUNT_POINT" -o url="$ENDPOINT" -o use_path_request_style -o allow_other -o passwd_file=/etc/passwd-s3fs || true
  if ! mountpoint -q "$MOUNT_POINT"; then
    echo "$(date '+%F %T') s3fs mount failed; falling back to sync" | tee -a "$LOG_FILE"
    ensure_sync_tools
    perform_sync
  fi
fi
