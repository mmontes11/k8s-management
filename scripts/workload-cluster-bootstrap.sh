#!/bin/bash

set -euo pipefail

GITHUB_USER=${GITHUB_USER:-mmontes11}
GITHUB_REPO=${GITHUB_REPO:-k8s-infrastructure}
GITHUB_BRANCH=${GITHUB_BRANCH:-main}
GITHUB_PATH=${GITHUB_PATH:-clusters/homelab-v2}
if [ -z "$GITHUB_TOKEN" ]; then
  echo "GITHUB_TOKEN environment variable must be provided"
  exit 1
fi
FLUX_VERSION=${FLUX_VERSION:-2.5.0}
KUBECONFIG=${KUBECONFIG:-kubeconfig} 
SECRETS_NAMESPACE=${SECRETS_NAMESPACE:-secrets}

# sealed secrets
kubectl create namespace "$SECRETS_NAMESPACE" \
  --kubeconfig=$KUBECONFIG \
  --dry-run=client -o yaml \
  | kubectl apply --kubeconfig=$KUBECONFIG -f -
kubectl create secret tls \
  --kubeconfig=$KUBECONFIG \
  -n "$SECRETS_NAMESPACE" \
  sealed-secrets-key \
  --cert=certs/tls.crt --key=certs/tls.key \
  --dry-run=client -o yaml \
  | kubectl apply --kubeconfig=$KUBECONFIG -f -
kubectl label secret \
  --kubeconfig=$KUBECONFIG \
  -n "$SECRETS_NAMESPACE" \
  sealed-secrets-key \
  sealedsecrets.bitnami.com/sealed-secrets-key=active \
  --overwrite

# flux
curl -s https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION} bash -s -
# TODO: remove tolerations when worker nodes without taints are available
flux bootstrap github \
  --kubeconfig=$KUBECONFIG \
  --toleration-keys="node-role.kubernetes.io/control-plane" \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=$GITHUB_BRANCH \
  --path=$GITHUB_PATH \
  --personal \
  --private=false