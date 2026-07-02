#!/bin/bash

set -euo pipefail

source ./scripts/lib.sh

S3_ALIAS=${S3_ALIAS:-s3}
S3_URL=${S3_URL:-https://s3.mmontes-internal.duckdns.org/}
S3_BUCKET=${S3_BUCKET:-management}
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
  if [ -z "${S3_ACCESS_KEY:-}" ] || [ -z "${S3_SECRET_KEY:-}" ]; then
    echo "❌ S3 credentials are not set. Please set S3_ACCESS_KEY and S3_SECRET_KEY."
    exit 1
  fi
  install_rclone

  echo "🪣 Connecting to S3"
  configure_s3_remote "$S3_ALIAS"

  echo "🪣 Pulling backups from S3"
  rclone copy "$S3_ALIAS:$S3_BUCKET/$BACKUPS_DIR" .
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
