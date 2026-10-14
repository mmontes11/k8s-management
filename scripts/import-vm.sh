#!/bin/bash

set -euo pipefail

# import-vm.sh
#
# Import a Proxmox VM that was recreated by hand (e.g. restored from a Proxmox
# backup) back into an existing, already-provisioned Cluster API ProxmoxMachine.
# Works for any machine - control-plane or worker.
#
# The Proxmox host is reached over SSH (the local machine does not need qm
# installed). The script performs exactly two changes and nothing else:
#
#   1. Rename the Proxmox VM so its `name` matches the ProxmoxMachine object
#      name. This is the only Proxmox-side write (the provider's FindVM adoption
#      path looks the VM up by ID and then requires the name to match exactly).
#   2. Set spec.virtualMachineID on the ProxmoxMachine to the VM's VMID, via a
#      local kubectl patch.
#
# The VM config is read over SSH in a strictly read-only way (qm config only).
# The script never runs qm destroy, never powers a VM on/off, and does not
# destroy the redundant replacement VM. It also does not watch/wait for the
# adoption to converge; it prints the commands to verify it yourself.
#
# Inputs (all optional except the two K8s ones; see the runbook for details):
#   PROXMOX_HOST              Proxmox hypervisor host (SSH target)   [10.0.0.11]
#   PROXMOX_USER              SSH user on the Proxmox host           [root]
#   PROXMOX_VM_ID             numeric VMID of the restored VM        (required)
#   KUBERNETES_PROXMOX_MACHINE  name of the ProxmoxMachine object    (required)
#   KUBERNETES_NAMESPACE      namespace of the ProxmoxMachine object [homelab]
#   SSH_OPTS                  extra options passed to ssh            []
#
# Safety:
#   * It refuses to run against a ProxmoxMachine that is not already provisioned
#     (no spec.providerID), because adopting a mid-provisioning machine could
#     re-trigger cloning.
#   * Renaming a VM only changes its label - VMID, disks and data are untouched.
#
# Provider evidence (why these two changes are sufficient) is in
# docs/runbook-adopt-proxmox-vm.md.

PROXMOX_HOST=${PROXMOX_HOST:-10.0.0.11}
PROXMOX_USER=${PROXMOX_USER:-root}
SSH_OPTS=${SSH_OPTS:-}
PROXMOX_VM_ID=${PROXMOX_VM_ID:-}
KUBERNETES_PROXMOX_MACHINE=${KUBERNETES_PROXMOX_MACHINE:-}
KUBERNETES_NAMESPACE=${KUBERNETES_NAMESPACE:-homelab}

log() { echo "[import-vm] $*"; }
die() { echo "[import-vm] ERROR: $*" >&2; exit 1; }

# Run a qm command on the Proxmox host over SSH.
px() { ssh $SSH_OPTS "$PROXMOX_USER@$PROXMOX_HOST" "qm $*"; }

[ -n "$PROXMOX_VM_ID" ]   || die "PROXMOX_VM_ID is mandatory"
[ -n "$KUBERNETES_PROXMOX_MACHINE" ] || die "KUBERNETES_PROXMOX_MACHINE is mandatory"
[[ "$PROXMOX_VM_ID" =~ ^[0-9]+$ ]] || die "PROXMOX_VM_ID must be a numeric VMID (got '$PROXMOX_VM_ID')"
command -v ssh     &>/dev/null || die "ssh not found in PATH"
command -v kubectl &>/dev/null || die "kubectl not found in PATH"
command -v jq      &>/dev/null || die "jq not found in PATH"

log "Checking prerequisites (Proxmox=$PROXMOX_USER@$PROXMOX_HOST namespace=$KUBERNETES_NAMESPACE)"

px config "$PROXMOX_VM_ID" >/dev/null 2>&1 \
  || die "could not run 'qm config $PROXMOX_VM_ID' on $PROXMOX_USER@$PROXMOX_HOST (check SSH access and the VMID)"

kubectl get "proxmoxmachine/$KUBERNETES_PROXMOX_MACHINE" -n "$KUBERNETES_NAMESPACE" >/dev/null 2>&1 \
  || die "ProxmoxMachine/$KUBERNETES_PROXMOX_MACHINE not found in namespace $KUBERNETES_NAMESPACE"

pm_data=$(kubectl get "proxmoxmachine/$KUBERNETES_PROXMOX_MACHINE" -n "$KUBERNETES_NAMESPACE" -o json)
cur_provider_id=$(printf '%s' "$pm_data" | jq -r '.spec.providerID // empty')
cur_vm_id=$(printf '%s' "$pm_data" | jq -r '.spec.virtualMachineID // empty')

[ -n "$cur_provider_id" ] \
  || die "ProxmoxMachine/$KUBERNETES_PROXMOX_MACHINE has no spec.providerID yet; it does not look provisioned. This script only adopts already-provisioned machines. Refusing."

# Read the VM config over SSH (strictly read-only).
vm_config=$(px config "$PROXMOX_VM_ID")
bios_uuid=$(printf '%s\n' "$vm_config" \
  | grep -oE 'uuid=[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}' | head -n1 | cut -d= -f2)
[ -n "$bios_uuid" ] || die "could not read the smbios1 uuid from VM $PROXMOX_VM_ID"
cur_name=$(printf '%s\n' "$vm_config" | awk '/^name:/{print $2}')
log "VM $PROXMOX_VM_ID: name='${cur_name:-<unset>}' smbios1=$bios_uuid"
log "ProxmoxMachine/$KUBERNETES_PROXMOX_MACHINE: providerID=$cur_provider_id virtualMachineID=${cur_vm_id:-<unset>}"

# Change 1: align the Proxmox VM name to the ProxmoxMachine object name
# (the single Proxmox-side write).
if [ "$cur_name" = "$KUBERNETES_PROXMOX_MACHINE" ]; then
  log "VM name already matches the ProxmoxMachine name ('$KUBERNETES_PROXMOX_MACHINE'); skipping rename"
else
  log "Renaming Proxmox VM $PROXMOX_VM_ID: '$cur_name' -> '$KUBERNETES_PROXMOX_MACHINE'"
  px set "$PROXMOX_VM_ID" --name "$KUBERNETES_PROXMOX_MACHINE"
  log "  now: $(px config "$PROXMOX_VM_ID" | awk '/^name:/{print $2}')"
fi

# Change 2: point the ProxmoxMachine at the VM (local kubectl patch only).
log "Setting spec.virtualMachineID=$PROXMOX_VM_ID on ProxmoxMachine/$KUBERNETES_PROXMOX_MACHINE"
kubectl patch "proxmoxmachine/$KUBERNETES_PROXMOX_MACHINE" -n "$KUBERNETES_NAMESPACE" --type merge -p \
  "$(jq -n --argjson vmid "$PROXMOX_VM_ID" '{spec:{virtualMachineID:$vmid}}')"

log "Done. The provider will reconcile; verify with (no changes are made by these):"
log "  kubectl get proxmoxmachine/$KUBERNETES_PROXMOX_MACHINE -n $KUBERNETES_NAMESPACE -o yaml   # status.vmStatus: running, status.providerID: proxmox://$bios_uuid"
log "  kubectl get machine -n $KUBERNETES_NAMESPACE -o yaml | jq '.items[] | select(.spec.infrastructureRef.name==\"$KUBERNETES_PROXMOX_MACHINE\") | {name:.metadata.name, ready:.status.ready, nodeRef:.status.nodeRef, providerID:.spec.providerID}'"
log "  # confirm no new replacement machine appears over a few reconcile cycles:"
log "  kubectl get machine -n $KUBERNETES_NAMESPACE"
log "  # if this is a control-plane machine, also confirm the control plane stopped scaling:"
log "  kubectl get taloscontrolplane -n $KUBERNETES_NAMESPACE   # expect Resized unchanged, no new machine"
