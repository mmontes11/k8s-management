#!/bin/bash

set -euo pipefail

echo "🔐 Setting up firewall rules..."
ufw allow 6443/tcp # API Server
ufw allow from 10.42.0.0/16 to any # Pod CIDR
ufw allow from 10.43.0.0/16 to any # Service CIDR

K3S_VERSION=${K3S_VERSION:-"v1.33.1+k3s1"}

echo "🚀 Starting K3s..."
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  sh -s - server \
    --cluster-init \
    --write-kubeconfig-mode=644 \
    --disable traefik \
    --disable servicelb \
    --disable cloud-controller \
    --disable network-policy \
    --disable helm-controller
