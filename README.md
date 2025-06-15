# k8s-management
🐢 Bootstrap Kubernetes clusters with Cluster API

This repo sets up a management cluster based on [k3s](https://github.com/k3s-io/k3s/), installs [Cluster API](https://github.com/kubernetes-sigs/cluster-api) and performs bootstrapping.

### Installation

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

### Backup and Restore

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