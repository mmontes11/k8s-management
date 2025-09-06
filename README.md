# 🐢 k8s-management
Bootstrap Kubernetes clusters with Cluster API, Talos and Proxmox.

This repo sets up a [k3s](https://github.com/k3s-io/k3s) management cluster, installs [Cluster API](https://cluster-api.sigs.k8s.io/) and performs bootstrapping of [Talos](https://www.talos.dev/) workload clusters on top of [Proxmox](https://www.proxmox.com/) infrastructure.

The workload cluster is bootstrapped by [Flux](https://fluxcd.io/) using the [k8s-infrastructure](https://github.com/mmontes11/k8s-infrastructure) repository.

### Install

Install the k3s management cluster:

```bash
sudo bash scripts/cluster.sh
```

Credentials for the management cluster will be available at the `/etc/rancher/k3s/k3s.yaml` file.

### Bootstrap

To install Cluster API and bootstrap a workload cluster, set the `GITHUB_TOKEN` environment variable and run:

```bash
sudo \
GITHUB_TOKEN="$GITHUB_TOKEN" \
bash scripts/bootstrap.sh
```

### Configure access to the workload cluster

To configure access to the workload cluster, set the `WORKLOAD_CLUSTER` environment variable and run:

````bash
WORKLOAD_CLUSTER="$WORKLOAD_CLUSTER" \
bash scripts/workload-cluster-credentials.sh
````

Credentials will be available in the `kubeconfig` and `talosconfig` files in the current directory. Set the following aliases to temporarily use the workload cluster:

```bash
alias k="kubectl --kubeconfig=kubeconfig"
alias t="talosctl --talosconfig=talosconfig"
```

### Bootstrap workload cluster

To deploy the infrastructure components in the workload cluster, set the `GITHUB_TOKEN` environment variable and run run following script to bootstrap the [k8s-infrastructure](https://github.com/mmontes11/k8s-infrastructure) repository using flux:

````bash
sudo \
GITHUB_TOKEN="$GITHUB_TOKEN" \
bash scripts/workload-cluster-bootstrap.sh
````

### Upgrade

To upgrade the management cluster, set the `K3S_VERSION` environment variable to the desired version and run:

```bash
sudo \
K3S_VERSION="v1.33.1+k3s1" \
bash scripts/cluster.sh
```

### Backup

To take an on-demand backup of the management cluster and push it to object storage, run:

```bash
sudo \
MINIO_ACCESS_KEY="<access-key>" \
MINIO_SECRET_KEY="<secret-key>" \
bash scripts/backup.sh
```

### Restore

To restore a backup in a existing cluster, select the backup to restore with `SNAPSHOT_NAME` and and run:

```bash
sudo \
MINIO_ACCESS_KEY="<access-key>" \
MINIO_SECRET_KEY="<secret-key>" \
SNAPSHOT_NAME="on-demand-management-1749986019" \
bash scripts/restore.sh
```

### Uninstall

To uninstall the k3s management cluster, run:

```bash
k3s-uninstall.sh
``` 

### Reference

- [Blog post](https://a-cup-of.coffee/blog/talos-capi-proxmox/) from [@qjoly](https://github.com/qjoly/).
- [cluster-api-operator](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api-operator)
- [cluster-api](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api)
- [cluster-api-ipam-provider-in-cluster](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api-ipam-provider-in-cluster)
- [cluster-api-provider-proxmox](https://doc.crds.dev/github.com/ionos-cloud/cluster-api-provider-proxmox)
- [cluster-api-control-plane-provider-talos](https://doc.crds.dev/github.com/siderolabs/cluster-api-control-plane-provider-talos)
- [cluster-api-bootstrap-provider-talos](https://doc.crds.dev/github.com/siderolabs/cluster-api-bootstrap-provider-talos)

### Alternative installation flavours

- [k8s-bootstrap](https://github.com/mmontes11/k8s-bootstrap): Kubeadm based installation.
- [k8s-bootstrap-talos](https://github.com/mmontes11/k8s-bootstrap-talos): Talos based installation.