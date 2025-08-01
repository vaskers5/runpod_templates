#!/usr/bin/env bash
set -euo pipefail

BUCKET="${S3_BUCKET:-}"
MOUNT_POINT="${S3_MOUNT_POINT:-/mnt/s3}"
ACCESS_KEY="${S3__ACCESS_KEY:-}"
SECRET_KEY="${S3__SECRET_KEY:-}"
ENDPOINT="${S3__ENDPOINT_URL:-}"

if [[ -z "$BUCKET" || -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$ENDPOINT" ]]; then
  echo "S3 mount variables not fully specified. Skipping mount."
  exit 0
fi

if ! command -v rclone >/dev/null 2>&1; then
  apt-get update && apt-get install -y --no-install-recommends rclone && rm -rf /var/lib/apt/lists/*
fi

if [[ ! -e /dev/fuse ]]; then
  if command -v modprobe >/dev/null 2>&1; then
    modprobe fuse 2>/dev/null || true
  fi
  [[ -e /dev/fuse ]] || { mknod -m 666 /dev/fuse c 10 229 2>/dev/null || true; }
fi

if [[ ! -e /dev/fuse ]]; then
  echo "FUSE device /dev/fuse not found. Unable to mount with rclone." >&2
  exit 1
fi

mkdir -p /root/.config/rclone
cat <<RCONF >/root/.config/rclone/rclone.conf
[s3]
type = s3
provider = Minio
env_auth = true
endpoint = ${ENDPOINT}
RCONF

mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
  echo "S3 already mounted at $MOUNT_POINT"
else
  AWS_ACCESS_KEY_ID="$ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SECRET_KEY" \
    AWS_EC2_METADATA_DISABLED=true \
    rclone mount "s3:$BUCKET" "$MOUNT_POINT" \
      --allow-other --daemon
fi
