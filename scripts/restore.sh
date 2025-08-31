#!/bin/bash

set -euo pipefail

source ./scripts/lib.sh

MINIO_ALIAS=${MINIO_ALIAS:-minio}
MINIO_URL=${MINIO_URL:-https://10.0.0.90:443}
MINIO_BUCKET=${MINIO_BUCKET:-management}
BACKUPS_DIR=${BACKUPS_DIR:-backups}
if [ -z "${SNAPSHOT_NAME:-}" ]; then
  echo "❌ SNAPSHOT_NAME environment variable is mandatory"
  exit 1
fi

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SNAPSHOT_PATH="$CURDIR/../$BACKUPS_DIR"
SNAPSHOT_RESTORE_PATH="$SNAPSHOT_PATH/$SNAPSHOT_NAME"
TOKEN_PATH="$SNAPSHOT_PATH/token"

if [ ! -d "$BACKUPS_DIR" ]; then
  if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
    echo "❌ MinIO credentials are not set. Please set MINIO_ACCESS_KEY and MINIO_SECRET_KEY."
    exit 1
  fi
  install_mc

  echo "🪣 Connecting to MinIO"
  mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure

  echo "🪣 Pulling backups from MinIO"
  mc cp --recursive --insecure "$MINIO_ALIAS/$MINIO_BUCKET/$BACKUPS_DIR" "$BACKUPS_DIR"
fi

echo "🛑 Stopping K3s..."
systemctl stop k3s || true

echo "🔁 Performing cluster reset with snapshot..."
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path="$SNAPSHOT_RESTORE_PATH" \
  --token="$(cat "$TOKEN_PATH")"

echo "🚀 Starting K3s..."
systemctl start k3s
