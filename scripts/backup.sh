#!/bin/bash

set -euo pipefail

source ./scripts/lib.sh

S3_ALIAS=${S3_ALIAS:-s3}
S3_URL=${S3_URL:-https://s3.mmontes-internal.duckdns.org/}
S3_BUCKET=${S3_BUCKET:-management}
BACKUPS_DIR=${BACKUPS_DIR:-backups}

if [ -z "${S3_ACCESS_KEY:-}" ] || [ -z "${S3_SECRET_KEY:-}" ]; then
  echo "❌ S3 credentials are not set. Please set S3_ACCESS_KEY and S3_SECRET_KEY."
  exit 1
fi

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SNAPSHOT_PATH="$CURDIR/../$BACKUPS_DIR"
TOKEN_PATH="$SNAPSHOT_PATH/token"

install_rclone

echo "🪣 Connecting to S3"
configure_s3_remote "$S3_ALIAS"

mkdir -p "$SNAPSHOT_PATH"

echo "💾 Creating etcd snapshot..."
k3s etcd-snapshot save --dir "$SNAPSHOT_PATH"

echo "🔐 Saving cluster token..."
cp /var/lib/rancher/k3s/server/token "$TOKEN_PATH"

echo "✅ Backup completed: $SNAPSHOT_PATH, token saved to $TOKEN_PATH"

echo "🪣 Pushing backup to S3"
rclone copy "$SNAPSHOT_PATH" "$S3_ALIAS:$S3_BUCKET/"