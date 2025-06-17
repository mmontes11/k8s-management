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

# sealed secrets
SECRETS_NAMESPACE=${SECRETS_NAMESPACE:-sealed-secrets}
kubectl create namespace "$SECRETS_NAMESPACE" \
  --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl create secret tls \
  -n "$SECRETS_NAMESPACE" \
  sealed-secrets-key \
  --cert=certs/tls.crt --key=certs/tls.key \
  --dry-run=client -o yaml \
  | kubectl apply -f -
kubectl label secret \
  -n "$SECRETS_NAMESPACE" \
  sealed-secrets-key \
  sealedsecrets.bitnami.com/sealed-secrets-key=active \
  --overwrite

# flux
curl -s https://fluxcd.io/install.sh | FLUX_VERSION=${FLUX_VERSION:-2.5.0} bash -s -
KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml} \
flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$GITHUB_REPO \
  --branch=$GITHUB_BRANCH \
  --path=$GITHUB_PATH \
  --personal \
  --private=false