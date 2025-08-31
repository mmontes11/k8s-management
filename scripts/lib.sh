#!/bin/bash

set -euo pipefail

install_mc() {
  if ! command -v mc &>/dev/null; then
    echo "⬇️ Installing MinIO client (mc)..."

    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64) MC_ARCH="linux-amd64" ;;
      aarch64) MC_ARCH="linux-arm64" ;;
      *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    tmpfile=$(mktemp)
    wget -qO "$tmpfile" "https://dl.min.io/client/mc/release/$MC_ARCH/mc"
    chmod +x "$tmpfile"
    sudo mv "$tmpfile" /usr/bin/mc
    echo "✅ mc installed to /usr/bin/mc ($MC_ARCH)"
  else
    echo "✅ mc already installed: $(command -v mc)"
  fi
}
