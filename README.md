# k8s-management
🐢 Bootstrap Kubernetes clusters with Cluster API, Talos and Proxmox.

This repo sets up a [k3s](https://github.com/k3s-io/k3s) management cluster, installs [Cluster API](https://cluster-api.sigs.k8s.io/) and performs bootstrapping of [Talos](https://www.talos.dev/) workload clusters on top of [Proxmox](https://www.proxmox.com/) infrastructure.

__🚧 WIP 🚧__

Inspired by this [blog post](https://a-cup-of.coffee/blog/talos-capi-proxmox/) from [@qjoly](https://github.com/qjoly/).

### Install

Install the k3s management cluster:

```bash
sudo bash scripts/cluster.sh
```

To create the cluster from a snapshot, set the `SNAPSHOT_PATH` and `TOKEN_PATH` environment variables using absolute paths:

```bash
sudo \
SNAPSHOT_PATH="$(pwd)/backups/on-demand-management-1749986019" \
TOKEN_PATH="$(pwd)/backups/token" \
bash scripts/cluster.sh
```

Credentials for the management cluster will be available at the `/etc/rancher/k3s/k3s.yaml` file.

### Bootstrap

To install Cluster API and bootstrap a workload cluster, set the `GITHUB_TOKEN` environment variable and run:

```bash
sudo \
GITHUB_USER=mmontes11 \
GITHUB_REPO=k8s-management \ 
GITHUB_BRANCH=main \
GITHUB_PATH=clusters/management \
GITHUB_TOKEN="$GITHUB_TOKEN" \
bash scripts/bootstrap.sh
```

### Configure access to the workload cluster

To configure access to the workload cluster, set the `WORKLOAD_CLUSTER` environment variable and run:

````bash
WORKLOAD_CLUSTER="$WORKLOAD_CLUSTER" \
bash scripts/workload-cluster-credentials.sh
````

Credentials will be available in the `kubeconfig` and `talosconfig` files in the current directory.

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

### Backup and restore

To take an on-demand backup of the management cluster in the local `backups` directory, run:

```bash
sudo bash scripts/backup.sh
```
Alternatively, scheduled backups available in `/var/lib/rancher/k3s/server/db/snapshots` can be used.

To restore a backup in a existing cluster, set the `SNAPSHOT_PATH` and `TOKEN_PATH` environment variables using absolute paths and run:

```bash
sudo \
SNAPSHOT_PATH="$(pwd)/backups/on-demand-management-1749986019" \
TOKEN_PATH="$(pwd)/backups/token" \
bash scripts/restore.sh
```

### Uninstall

To uninstall the k3s management cluster, run:

```bash
k3s-uninstall.sh
``` 