#!/usr/bin/env bash
set -euo pipefail

BUCKET="${S3_BUCKET:-}"   # required bucket name
MOUNT_POINT="${S3_MOUNT_POINT:-/mnt/s3}"
ACCESS_KEY="${S3__ACCESS_KEY:-}"
SECRET_KEY="${S3__SECRET_KEY:-}"
ENDPOINT="${S3__ENDPOINT_URL:-}"

if [[ -z "$BUCKET" || -z "$ACCESS_KEY" || -z "$SECRET_KEY" || -z "$ENDPOINT" ]]; then
  echo "S3 mount variables not fully specified. Skipping mount."
  exit 0
fi

# ensure s3fs is available
if ! command -v s3fs >/dev/null 2>&1; then
  apt-get update && apt-get install -y --no-install-recommends s3fs && rm -rf /var/lib/apt/lists/*
fi

# check that FUSE device exists and try to load module if missing
if [[ ! -e /dev/fuse ]]; then
  if command -v modprobe >/dev/null 2>&1; then
    modprobe fuse 2>/dev/null || true
  fi
fi

if [[ ! -e /dev/fuse ]]; then
  echo "FUSE device /dev/fuse not found. Falling back to 'aws s3 sync'." >&2
  if ! command -v aws >/dev/null 2>&1; then
    apt-get update && apt-get install -y --no-install-recommends awscli && rm -rf /var/lib/apt/lists/*
  fi
  mkdir -p "$MOUNT_POINT"
  aws s3 sync "s3://$BUCKET" "$MOUNT_POINT" --endpoint-url "$ENDPOINT"
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
  s3fs "$BUCKET" "$MOUNT_POINT" -o url="$ENDPOINT" -o use_path_request_style -o allow_other -o passwd_file=/etc/passwd-s3fs
fi
