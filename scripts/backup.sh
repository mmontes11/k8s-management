#!/bin/bash

set -euo pipefail

source ./scripts/lib.sh

MINIO_ALIAS=${MINIO_ALIAS:-minio}
MINIO_URL=${MINIO_URL:-https://10.0.0.90:443}
MINIO_BUCKET=${MINIO_BUCKET:-management}
BACKUPS_DIR=${BACKUPS_DIR:-backups}

if [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
  echo "❌ MinIO credentials are not set. Please set MINIO_ACCESS_KEY and MINIO_SECRET_KEY."
  exit 1
fi

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SNAPSHOT_PATH="$CURDIR/../$BACKUPS_DIR"
TOKEN_PATH="$SNAPSHOT_PATH/token"

install_mc

echo "🪣 Connecting to MinIO"
mc alias set "$MINIO_ALIAS" "$MINIO_URL" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY" --insecure

mkdir -p "$SNAPSHOT_PATH"

echo "💾 Creating etcd snapshot..."
k3s etcd-snapshot save --dir "$SNAPSHOT_PATH"

echo "🔐 Saving cluster token..."
cp /var/lib/rancher/k3s/server/token "$TOKEN_PATH"

echo "✅ Backup completed: $SNAPSHOT_PATH, token saved to $TOKEN_PATH"

echo "🪣 Pushing backup to MinIO"
mc cp --recursive --insecure "$SNAPSHOT_PATH" "$MINIO_ALIAS/$MINIO_BUCKET/"