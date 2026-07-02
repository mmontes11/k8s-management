#!/bin/bash

set -euo pipefail

install_rclone() {
  if ! command -v rclone &>/dev/null; then
    echo "⬇️ Installing rclone..."
    curl -s https://rclone.org/install.sh | sudo bash
    echo "✅ rclone installed: $(command -v rclone)"
  else
    echo "✅ rclone already installed: $(command -v rclone)"
  fi
}

# configure_s3_remote exports the RCLONE_CONFIG_* env vars for a S3 remote
# named $1, so rclone can be used without writing a config file to disk.
configure_s3_remote() {
  local remote_upper
  remote_upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  export "RCLONE_CONFIG_${remote_upper}_TYPE=s3"
  export "RCLONE_CONFIG_${remote_upper}_PROVIDER=SeaweedFS"
  export "RCLONE_CONFIG_${remote_upper}_ENV_AUTH=false"
  export "RCLONE_CONFIG_${remote_upper}_ACCESS_KEY_ID=$S3_ACCESS_KEY"
  export "RCLONE_CONFIG_${remote_upper}_SECRET_ACCESS_KEY=$S3_SECRET_KEY"
  export "RCLONE_CONFIG_${remote_upper}_ENDPOINT=$S3_URL"
}
