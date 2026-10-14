# Runbook: Import a manually restored Proxmox VM into Cluster API

Use this when a Proxmox VM — control-plane or worker — has been recreated by hand (for example, restored from a Proxmox backup) and is no longer part of Cluster API state, so its owning controller (the `TalosControlPlane` for control-plane machines, the `MachineDeployment` for workers) has started provisioning a replacement machine. The goal is to make CAPI track the restored VM instead of the replacement, stop further provisioning, and keep the node operable.

Repointing the existing `ProxmoxMachine` is preferred over creating a brand-new `Machine` by hand: it avoids a race in which the controller recreates a machine when the owned count momentarily drops to zero, avoids hand-wiring an `ownerReference` onto a controller-owned object, and lets the normal controllers keep the state consistent.

The two changes are identical for every machine. The concrete `Steps` / `Verification` / `Rollback` below are the control-plane case (restored VM `104`); apply the same two changes to any machine by substituting its VMID, `ProxmoxMachine` name and namespace.

## How the Proxmox provider adopts an existing VM

The `ProxmoxMachine` controller resolves which VM it owns in [`FindVM`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/find.go):

- It reads the VMID from `spec.virtualMachineID` ([`scope.GetVirtualMachineID`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/pkg/scope/machine.go)) and the hypervisor from `status.proxmoxNode` ([`scope.LocateProxmoxNode`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/pkg/scope/machine.go)), then looks the VM up **by ID** — it never clones when a VMID is set.
- It then requires the VM's Proxmox `name` to **exactly equal the `ProxmoxMachine` object name**. On a mismatch it treats the VM as "not initialized" and requeues — it does not clone or destroy anything.
- Once the VM is found and the machine is already in its terminal (provisioned) state, the create/clone, static-IP, bootstrap and power steps are each gated by the `VMProvisioned` condition reason and are skipped. The controller only re-points `status.providerID` to the VM's real SMBIOS UUID and marks the machine ready.

So adoption is two manual inputs — point `spec.virtualMachineID` at the restored VMID, and make the Proxmox VM `name` match the `ProxmoxMachine` name — and the CAPI `Machine` controller then links the Kubernetes node automatically via `providerID` matching.

## Helper script

`scripts/import-vm.sh` performs the two inputs above and nothing else. It reaches the Proxmox host over SSH (the local machine does not need `qm` installed) and does a local `kubectl` patch against the management cluster. It works for any `ProxmoxMachine`, control-plane or worker:

```bash
PROXMOX_HOST=10.0.0.11 \
PROXMOX_USER=root \
PROXMOX_VM_ID=104 \
KUBERNETES_PROXMOX_MACHINE=controlplane-758h2 \
KUBERNETES_NAMESPACE=homelab \
scripts/import-vm.sh
```

### Script inputs

| Variable | Default | Meaning |
| --- | --- | --- |
| `PROXMOX_HOST` | `10.0.0.11` | Proxmox hypervisor hostname/IP (reached over SSH) |
| `PROXMOX_USER` | `root` | SSH user on the Proxmox host |
| `PROXMOX_VM_ID` | _required_ | Numeric VMID of the restored VM on the Proxmox host |
| `KUBERNETES_PROXMOX_MACHINE` | _required_ | Name of the `ProxmoxMachine` Kubernetes object to repoint — a K8s resource, not a VM |
| `KUBERNETES_NAMESPACE` | `homelab` | Namespace of that `ProxmoxMachine` object |
| `SSH_OPTS` | _(empty)_ | Extra options passed to `ssh` (e.g. `-p <port>`, `-i <key>`) |

`PROXMOX_*` are the Proxmox-side inputs; `KUBERNETES_*` are the Kubernetes-side inputs.

What it does:

1. Reads the VM config over SSH in a strictly read-only way (`qm config <vmid>` only) to confirm the VMID, current name and SMBIOS UUID.
2. Renames the Proxmox VM to match the `ProxmoxMachine` name (`qm set <vmid> name <name>`) — the single Proxmox-side write; VMID, disks and data are untouched.
3. Sets `spec.virtualMachineID` on the `ProxmoxMachine` via a local `kubectl patch`.

What it deliberately does **not** do: no `qm destroy`, no power on/off, no disk operations, no watching/waiting loop, and it does not destroy the redundant replacement VM. It refuses to run against a `ProxmoxMachine` that is not already provisioned (no `spec.providerID`). When it finishes it prints the read-only commands to verify the adoption yourself.

## Why this is enough (provider evidence)

The two changes above are exactly what the adoption path requires. Each claim maps to provider code:

- It looks the VM up **by ID** (it never clones when a VMID is set) — [`FindVM`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/find.go).
- The VM's Proxmox `name` must **exactly equal** the `ProxmoxMachine` name; a mismatch requeues ("not initialized") and never clones or destroys — [`FindVM`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/find.go).
- The fields it reads come from `spec.virtualMachineID` / `status.proxmoxNode` — [`scope.GetVirtualMachineID`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/pkg/scope/machine.go), [`scope.LocateProxmoxNode`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/pkg/scope/machine.go).
- The clone, static-IP, bootstrap and power steps are each gated by the machine's provisioning condition reason, so an already-provisioned machine is only re-pointed — [`reconcileBootstrapData`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/bootstrap.go), [`reconcileIPAddresses`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/ip.go), [`reconcilePowerState`](https://github.com/ionos-cloud/cluster-api-provider-proxmox/blob/main/internal/service/vmservice/power.go).
- After `FindVM` succeeds the provider records the VM's real SMBIOS UUID as the provider ID, and the CAPI `Machine` controller links the Node to the `Machine` by that ID — no hand-wiring of `ownerReference` needed.
- Once the machine counts toward the owner, scaling stops — the `TalosControlPlane` (control-plane) does so in [`TalosControlPlaneReconciler.scaleUpControlPlane`](https://github.com/siderolabs/cluster-api-control-plane-provider-talos/blob/main/controllers/scale.go), and the CAPI `MachineDeployment` (workers) reconciles its replica count the same way.

> The links point at the providers' `main` branches (currently CAPMOX `v1alpha2` / Talos control-plane `v1alpha3`). The running cluster is on `v1alpha1`. The load-bearing contracts — `FindVM` by-ID lookup, the exact name-match requirement, and the reason-gated provisioning steps — are the same across these versions; only the condition-reason constant names differ.

## Prerequisites

- `kubectl` configured against the management cluster (where `TalosControlPlane` / `Machine` / `ProxmoxMachine` live — namespace `homelab` here).
- `qm` access on the Proxmox hypervisor (or SSH to it, for the helper script).
- Identify the objects:
  - Restored VM — VMID `104`, Proxmox name `controlplane-6ck8t`, SMBIOS UUID `8199db4d-969f-47a7-a9e6-81e39565bca0`, MAC `BC:24:11:7C:FB:AA`, IP `10.0.0.40`, hypervisor `proxmox`.
  - CAPI objects — `Machine/controlplane-tjvrx` and `ProxmoxMachine/controlplane-758h2` (ns `homelab`).
  - The replacement VM that the provider cloned (here at `10.0.0.45`) — this is the one you will destroy.
- Confirm the restored node is a healthy control-plane member before starting:
  - `talosctl -n 10.0.0.40 --nodes 10.0.0.40 version`
  - `kubectl get nodes`
- **Back up the management cluster first** (see the [Backup](../README.md#backup) / [Restore](../README.md#restore) sections in the README) before any surgery.

## Steps

1. Rename the restored VM's Proxmox `name` to match the `ProxmoxMachine` object name. This only changes the VM label — VMID, disks and data are untouched.

   ```bash
   qm set 104 --name controlplane-758h2
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

   Double-check the VMID. Destroying VM `104` would take down the real control plane.

5. Optional — if a pool `IPAddress` object for `10.0.0.45` still exists for this machine, release it to free the IPAM pool slot.

## Verification

- `talosctl -n 10.0.0.40 --nodes 10.0.0.40 ...` works and the node is the control-plane member.
- `kubectl get machines -n homelab` shows the single control-plane machine `Ready`; watch for a few reconcile cycles to confirm no new machine appears.
- `kubectl get proxmoxmachine/controlplane-758h2 -n homelab` is stable at VMID `104` (not re-cloning).

## Rollback

Set `spec.virtualMachineID` back to the replacement VMID and rename VM `104`'s Proxmox `name` back to `controlplane-6ck8t`. Keep the replacement VM around until the adoption is verified stable, so this rollback is available.

## Caveats

- The owning controller counts its owned machines against the desired replica count — the `TalosControlPlane` (label `cluster.x-k8s.io/control-plane` + ownerReference) for control-plane, the `MachineDeployment` for workers. With the adopted machine counting, it is scale-stable and will not create another.
- This only works when the `ProxmoxMachine` is already in its terminal (provisioned) state. If it is still mid-provisioning (reason `Cloning` / `WaitingFor…`), repointing can re-trigger provisioning steps — only adopt an already-provisioned machine.
- Manual upgrades via `talosctl` are unaffected. To return to fully CAPI-managed control planes later, delete the adopted machine's objects and let the `TalosControlPlane` provision fresh.
