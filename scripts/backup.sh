#!/bin/bash

set -euo pipefail

CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
SNAPSHOT_PATH="$CURDIR/../backups"
TOKEN_PATH="$SNAPSHOT_PATH/token"

mkdir -p "$SNAPSHOT_PATH"

echo "💾 Creating etcd snapshot..."
k3s etcd-snapshot save --dir "$SNAPSHOT_PATH"

echo "🔐 Saving cluster token..."
cp /var/lib/rancher/k3s/server/token "$TOKEN_PATH"

echo "✅ Backup completed: $SNAPSHOT_PATH, token saved to $TOKEN_PATH"
