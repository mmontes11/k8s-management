# 🐢 k8s-management
Bootstrap Kubernetes clusters with Cluster API, Talos and Proxmox.

This repo sets up a [k3s](https://github.com/k3s-io/k3s) management cluster, installs [Cluster API](https://cluster-api.sigs.k8s.io/) and performs bootstrapping of [Talos](https://www.talos.dev/) workload clusters on top of [Proxmox](https://www.proxmox.com/) infrastructure.

The workload cluster is bootstrapped by [Flux](https://fluxcd.io/) using the [k8s-infrastructure](https://github.com/mmontes11/k8s-infrastructure) repository.

## Alternative installation flavours

- [k8s-bootstrap](https://github.com/mmontes11/k8s-bootstrap): Kubeadm based installation.
- [k8s-bootstrap-talos](https://github.com/mmontes11/k8s-bootstrap-talos): Talos based installation.

## Management cluster

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

```bash
WORKLOAD_CLUSTER="$WORKLOAD_CLUSTER" \
bash scripts/workload-cluster-credentials.sh
```

Credentials will be available in the `kubeconfig` and `talosconfig` files in the current directory. Set the following aliases to temporarily use the workload cluster:

```bash
alias k="kubectl --kubeconfig=kubeconfig"
alias t="talosctl --talosconfig=talosconfig"
```

### Bootstrap workload cluster

To deploy the infrastructure components in the workload cluster, set the `GITHUB_TOKEN` environment variable and run following script to bootstrap the [k8s-infrastructure](https://github.com/mmontes11/k8s-infrastructure) repository using flux:

```bash
sudo \
GITHUB_TOKEN="$GITHUB_TOKEN" \
bash scripts/workload-cluster-bootstrap.sh
```

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
S3_ACCESS_KEY="<access-key>" \
S3_SECRET_KEY="<secret-key>" \
bash scripts/backup.sh
```

### Restore

To restore a backup in a existing cluster, select the backup to restore with `SNAPSHOT_NAME` and and run:

```bash
sudo \
S3_ACCESS_KEY="<access-key>" \
S3_SECRET_KEY="<secret-key>" \
SNAPSHOT_NAME="on-demand-management-1749986019" \
bash scripts/restore.sh
```

### Uninstall

To uninstall the k3s management cluster, run:

```bash
k3s-uninstall.sh
```

## Workload cluster

### Template immutability

`ProxmoxMachineTemplate` and `TalosConfigTemplate` resources are **entirely immutable**. Any change to their `spec` (disk size, RAM, CPU, strategic patches, etc.) will be rejected by the webhook:

```
ProxmoxMachineTemplate.infrastructure.cluster.x-k8s.io "compute-large" is invalid: spec: Forbidden: ProxmoxMachineTemplate is immutable
```

To update a template, use one of these approaches:

**A) New name (safer, zero-downtime rollout):**
1. Create a new template (e.g. `compute-large-v2`) with the updated spec
2. Update the `infrastructureRef.name` (for `ProxmoxMachineTemplate`) and/or `bootstrap.configRef.name` (for `TalosConfigTemplate`) in the affected `MachineDeployment` resources
3. CAPI will rollout new machines using the new template and delete the old ones
4. Delete the old template after the rollout completes

**B) Same name (simpler, brief reconciliation gap):**
1. Delete the old template from Git
2. Flux deletes it from the cluster
3. Add the new template with the same name
4. Flux creates it — no `MachineDeployment` changes needed

Approach B works because `MachineDeployment` references templates by name, not UID. The reconciliation gap is brief (seconds to minutes) and the `MachineDeployment` will pick up the new template automatically.

### Runbooks

#### Adopt a manually restored control-plane VM into Cluster API

Use this when a control-plane VM has been recreated by hand (for example, restored from a Proxmox backup) and is no longer part of Cluster API state, so the `TalosControlPlane` has started provisioning a replacement machine. The goal is to make CAPI track the restored VM instead of the replacement, stop further provisioning, and keep the node operable manually with `talosctl`.

Repointing the existing `ProxmoxMachine` is preferred over creating a brand-new `Machine` by hand: it avoids a race in which the `TalosControlPlane` recreates a machine when the owned count momentarily drops to zero, avoids hand-wiring an `ownerReference` onto a controller-owned object, and lets the normal controllers keep the state consistent.

**How the Proxmox provider adopts an existing VM**

The `ProxmoxMachine` controller resolves which VM it owns in `FindVM`:

- It reads the VMID from `spec.virtualMachineID` and the hypervisor from `status.proxmoxNode`, then looks the VM up **by ID** — it never clones when a VMID is set.
- It then requires the VM's Proxmox `name` to **exactly equal the `ProxmoxMachine` object name**. On a mismatch it treats the VM as "not initialized" and requeues — it does not clone or destroy anything.
- Once the VM is found and the machine is already in its terminal (provisioned) state, the create/clone, static-IP, bootstrap and power steps are each gated by the `VMProvisioned` condition reason and are skipped. The controller only re-points `status.providerID` to the VM's real SMBIOS UUID and marks the machine ready.

So adoption is two manual inputs — point `spec.virtualMachineID` at the restored VMID, and make the Proxmox VM `name` match the `ProxmoxMachine` name — and the CAPI `Machine` controller then links the Kubernetes node automatically via `providerID` matching.

**Helper script**

`scripts/import-controlplane-vm.sh` performs the two inputs above and nothing else. It reaches the Proxmox host over SSH (the local machine does not need `qm` installed) and does a local `kubectl` patch against the management cluster:

```bash
PROXMOX_HOST=10.0.0.11 \
PROXMOX_USER=root \
PROXMOX_VM_ID=104 \
PROXMOX_MACHINE=controlplane-758h2 \
NAMESPACE=homelab \
scripts/import-controlplane-vm.sh
```

What it does — and only this:

1. Reads the VM config over SSH in a strictly read-only way (`qm config <vmid>` only) to confirm the VMID, current name and SMBIOS UUID.
2. Renames the Proxmox VM to match the `ProxmoxMachine` name (`qm set <vmid> name <name>`) — the single Proxmox-side write; VMID, disks and data are untouched.
3. Sets `spec.virtualMachineID` on the `ProxmoxMachine` via a local `kubectl patch`.

What it deliberately does **not** do: no `qm destroy`, no power on/off, no disk operations, no watching/waiting loop, and it does not destroy the redundant replacement VM. It refuses to run against a `ProxmoxMachine` that is not already provisioned (no `spec.providerID`). When it finishes it prints the read-only commands to verify the adoption yourself.

**Why this is enough (provider evidence)**

The provider resolves which VM a `ProxmoxMachine` owns in `FindVM`; the two changes above are exactly what that path requires:

- It reads the VMID from `spec.virtualMachineID` and the node from `status.proxmoxNode`, then looks the VM up **by ID** (it never clones when a VMID is set) — `FindVM()` in [vmservice/find.go](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/find.go).
- It then requires the VM's Proxmox `name` to **exactly equal the `ProxmoxMachine` name**; on a mismatch it treats the VM as "not initialized" and requeues — it does not clone or destroy (same file).
- The fields it reads come from `spec.virtualMachineID` / `status.proxmoxNode` — [pkg/scope/machine.go](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/pkg/scope/machine.go) (`GetVirtualMachineID`, `LocateProxmoxNode`).
- The clone, static-IP, bootstrap and power steps are each gated by the machine's provisioning condition reason, so an already-provisioned machine is only re-pointed — [bootstrap.go](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/bootstrap.go), [ip.go](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/ip.go), [power.go](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/power.go).
- After `FindVM` succeeds the provider records the VM's real SMBIOS UUID as the provider ID, and the CAPI `Machine` controller links the Node to the `Machine` by that ID — no hand-wiring of `ownerReference` needed.
- The `TalosControlPlane` stops scaling once the owned machine count equals `replicas` — `scaleUpControlPlane` in [taloscontrolplane controllers/scale.go](https://github.com/siderolabs/cluster-api-control-plane-provider-talos/blob/main/controllers/scale.go).

**Confidence — how to run it safely**

- It is read-only on Proxmox except for the single required rename. Run the read-only parts yourself first to sanity-check: `ssh root@10.0.0.11 qm config 104` (confirm name/uuid) and `kubectl get proxmoxmachine/controlplane-758h2 -n homelab -o yaml` (confirm `spec.providerID` is set, i.e. already provisioned).
- Before running it, back up the management cluster (see Backup/Restore above) and confirm the restored node is a healthy control-plane member (`talosctl -n 10.0.0.40 --nodes 10.0.0.40 version`).
- It is idempotent: if the VM name already matches it skips the rename, and re-running the patch is safe.
- The change is reversible (see Rollback): set `spec.virtualMachineID` back to the replacement VMID and rename the VM back. Keep the replacement VM around until the adoption is verified stable.

**Prerequisites**

- `kubectl` configured against the management cluster (where `TalosControlPlane` / `Machine` / `ProxmoxMachine` live — namespace `homelab` here).
- `qm` access on the Proxmox hypervisor.
- Identify the objects:
  - Restored VM — VMID `104`, Proxmox name `controlplane-6ck8t`, SMBIOS UUID `8199db4d-969f-47a7-a9e6-81e39565bca0`, MAC `BC:24:11:7C:FB:AA`, IP `10.0.0.40`, hypervisor `proxmox`.
  - CAPI objects — `Machine/controlplane-tjvrx` and `ProxmoxMachine/controlplane-758h2` (ns `homelab`).
  - The replacement VM that the provider cloned (here at `10.0.0.45`) — this is the one you will destroy.
- Confirm the restored node is a healthy control-plane member before starting:
  - `talosctl -n 10.0.0.40 --nodes 10.0.0.40 version`
  - `kubectl get nodes`
- **Back up the management cluster first** (see Backup/Restore above) before any surgery.

**Steps**

1. Rename the restored VM's Proxmox `name` to match the `ProxmoxMachine` object name. This only changes the VM label — VMID, disks and data are untouched.

   ```bash
   qm set 104 name controlplane-758h2
   qm config 104 | grep -E 'name|smbios1|macaddr'   # sanity check
   ```

2. Repoint the `ProxmoxMachine` at VM `104`. Do **not** delete the `ProxmoxMachine` — repointing keeps the `Machine`, its `ownerReference` to the `TalosControlPlane`, and its terminal provisioned state intact.

   ```bash
   kubectl patch proxmoxmachine/controlplane-758h2 -n homelab --type merge \
     -p '{"spec":{"virtualMachineID":104}}'
   ```

3. Wait ~30-60s for the controllers to reconcile, then verify:
   - `kubectl get proxmoxmachine/controlplane-758h2 -n homelab -o yaml` → `status.vmStatus: running`, `status.providerID: proxmox://8199db4d-969f-47a7-a9e6-81e39565bca0`, `VMProvisioned` ready.
   - `kubectl get machine/controlplane-tjvrx -n homelab -o yaml` → `status.nodeRef` now points to the real control-plane node (matched by `providerID`), `status.addresses` InternalIP `10.0.0.40`, `status.ready: true`, and the v1beta2 `NodeHealthy` / `NodeReady` conditions are `True`.
   - `kubectl get taloscontrolplane/controlplane -n homelab` → `Resized` `1/1`, no scaling.

4. Destroy the redundant replacement VM (the cloned one at `10.0.0.45`). Find its VMID — it is **not** `104` — and confirm before destroying:

   ```bash
   qm status <vmid>    # confirm this is the freshly cloned VM, not 104
   qm destroy <vmid>
   ```

   ⚠️ Double-check the VMID. Destroying VM `104` would take down the real control plane.

5. Optional — if a pool `IPAddress` object for `10.0.0.45` still exists for this machine, release it to free the IPAM pool slot.

**Verification**

- `talosctl -n 10.0.0.40 --nodes 10.0.0.40 ...` works and the node is the control-plane member.
- `kubectl get machines -n homelab` shows the single control-plane machine `Ready`; watch for a few reconcile cycles to confirm no new machine appears.
- `kubectl get proxmoxmachine/controlplane-758h2 -n homelab` is stable at VMID `104` (not re-cloning).

**Rollback**

Set `spec.virtualMachineID` back to the replacement VMID and rename VM `104`'s Proxmox `name` back to `controlplane-6ck8t`. Keep the replacement VM around until the adoption is verified stable, so this rollback is available.

**Caveats**

- The `TalosControlPlane` counts owned machines (label `cluster.x-k8s.io/control-plane` + ownerReference) against `spec.replicas`. With one adopted machine and `replicas: 1` it is scale-stable and will not create another.
- This only works when the `ProxmoxMachine` is already in its terminal (provisioned) state. If it is still mid-provisioning (reason `Cloning` / `WaitingFor…`), repointing can re-trigger provisioning steps — only adopt an already-provisioned machine.
- Manual upgrades via `talosctl` are unaffected. To return to fully CAPI-managed control planes later, delete the adopted machine's objects and let the `TalosControlPlane` provision fresh.

### Reference

- [Blog post](https://a-cup-of.coffee/blog/talos-capi-proxmox/) from [@qjoly](https://github.com/qjoly/).
- [cluster-api-operator](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api-operator)
- [cluster-api](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api)
- [cluster-api-ipam-provider-in-cluster](https://doc.crds.dev/github.com/kubernetes-sigs/cluster-api-ipam-provider-in-cluster)
- [cluster-api-provider-proxmox](https://doc.crds.dev/github.com/ionos-cloud/cluster-api-provider-proxmox)
- [cluster-api-control-plane-provider-talos](https://doc.crds.dev/github.com/siderolabs/cluster-api-control-plane-provider-talos)
- [cluster-api-bootstrap-provider-talos](https://doc.crds.dev/github.com/siderolabs/cluster-api-bootstrap-provider-talos)
