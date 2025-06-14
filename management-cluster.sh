#!/bin/bash

set -euo pipefail

# set up firewall
ufw allow 6443/tcp #apiserver
ufw allow from 10.42.0.0/16 to any #pods
ufw allow from 10.43.0.0/16 to any #services

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="v1.33.1+k3s1" \
  sh -s - server \
    --cluster-init \
    --write-kubeconfig-mode=644 \
    --disable traefik \
    --disable servicelb \
    --disable cloud-controller \
    --disable network-policy \
    --disable helm-controller
