#!/bin/bash

set -euo pipefail

if [ -z "${WORKLOAD_CLUSTER:-}" ]; then
  echo "❌ WORKLOAD_CLUSTER environment variable is mandatory"
  exit 1
fi

kubectl get secret cluster-kubeconfig -n $WORKLOAD_CLUSTER -o jsonpath="{.data.value}" | \
  base64 -d > kubeconfig
kubectl get secret cluster-talosconfig -n $WORKLOAD_CLUSTER -o jsonpath="{.data.talosconfig}" | \
  base64 -d > talosconfig