#!/bin/bash

set -euo pipefail

if [ -z "${SNAPSHOT_PATH:-}" ]; then
  echo "❌ SNAPSHOT_PATH environment variable is mandatory"
  exit 1
fi

if [ -z "${TOKEN_PATH:-}" ]; then
  echo "❌ TOKEN_PATH environment variable is mandatory"
  exit 1
fi

echo "🛑 Stopping K3s..."
systemctl stop k3s || true

echo "🔁 Performing cluster reset with snapshot..."
k3s server \
  --cluster-reset \
  --cluster-reset-restore-path="$SNAPSHOT_PATH" \
  --token="$(cat "$TOKEN_PATH")"

echo "🚀 Starting K3s..."
systemctl start k3s
