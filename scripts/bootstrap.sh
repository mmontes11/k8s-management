#!/bin/bash

set -eo pipefail

GITHUB_USER=${GITHUB_USER:-mmontes11}
GITHUB_REPO=${GITHUB_REPO:-k8s-management }
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
GITHUB_PATH=${GITHUB_PATH:-clusters/management}
if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN environment variable must be provided"
  exit 1
fi

curl -s https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION:-2.5.0} bash -s -

KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml} \
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=$GITHUB_BRANCH \
  --path=$GITHUB_PATH \
  --personal \
  --private=false