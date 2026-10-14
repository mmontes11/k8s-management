#!/bin/bash

set -euo pipefail

# import-controlplane-vm.sh
#
# Adopt a Proxmox VM that was recreated by hand (e.g. restored from a Proxmox
# backup) back into an existing, already-provisioned Cluster API ProxmoxMachine.
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
# Safety:
#   * It refuses to run against a ProxmoxMachine that is not already provisioned
#     (no spec.providerID), because adopting a mid-provisioning machine could
#     re-trigger cloning.
#   * Renaming a VM only changes its label - VMID, disks and data are untouched.
#
# Provider evidence (why these two changes are sufficient) is in the "Runbooks"
# section of the README.

PROXMOX_HOST=${PROXMOX_HOST:-10.0.0.11}
PROXMOX_USER=${PROXMOX_USER:-root}
SSH_OPTS=${SSH_OPTS:-}
PROXMOX_VM_ID=${PROXMOX_VM_ID:-}
PROXMOX_MACHINE=${PROXMOX_MACHINE:-}
NAMESPACE=${NAMESPACE:-homelab}

log() { echo "[import-controlplane-vm] $*"; }
die() { echo "[import-controlplane-vm] ERROR: $*" >&2; exit 1; }

# Run a qm command on the Proxmox host over SSH.
px() { ssh $SSH_OPTS "$PROXMOX_USER@$PROXMOX_HOST" "qm $*"; }

[ -n "$PROXMOX_VM_ID" ]   || die "PROXMOX_VM_ID is mandatory"
[ -n "$PROXMOX_MACHINE" ] || die "PROXMOX_MACHINE is mandatory"
[[ "$PROXMOX_VM_ID" =~ ^[0-9]+$ ]] || die "PROXMOX_VM_ID must be a numeric VMID (got '$PROXMOX_VM_ID')"
command -v ssh     &>/dev/null || die "ssh not found in PATH"
command -v kubectl &>/dev/null || die "kubectl not found in PATH"
command -v jq      &>/dev/null || die "jq not found in PATH"

log "Checking prerequisites (Proxmox=$PROXMOX_USER@$PROXMOX_HOST namespace=$NAMESPACE)"

px config "$PROXMOX_VM_ID" >/dev/null 2>&1 \
  || die "could not run 'qm config $PROXMOX_VM_ID' on $PROXMOX_USER@$PROXMOX_HOST (check SSH access and the VMID)"

kubectl get "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" >/dev/null 2>&1 \
  || die "ProxmoxMachine/$PROXMOX_MACHINE not found in namespace $NAMESPACE"

pm_data=$(kubectl get "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" -o json)
cur_provider_id=$(printf '%s' "$pm_data" | jq -r '.spec.providerID // empty')
cur_vm_id=$(printf '%s' "$pm_data" | jq -r '.spec.virtualMachineID // empty')

[ -n "$cur_provider_id" ] \
  || die "ProxmoxMachine/$PROXMOX_MACHINE has no spec.providerID yet; it does not look provisioned. This script only adopts already-provisioned machines. Refusing."

# Read the VM config over SSH (strictly read-only).
vm_config=$(px config "$PROXMOX_VM_ID")
bios_uuid=$(printf '%s\n' "$vm_config" \
  | grep -oE 'uuid=[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}' | head -n1 | cut -d= -f2)
[ -n "$bios_uuid" ] || die "could not read the smbios1 uuid from VM $PROXMOX_VM_ID"
cur_name=$(printf '%s\n' "$vm_config" | awk '/^name:/{print $2}')
log "VM $PROXMOX_VM_ID: name='${cur_name:-<unset>}' smbios1=$bios_uuid"
log "ProxmoxMachine/$PROXMOX_MACHINE: providerID=$cur_provider_id virtualMachineID=${cur_vm_id:-<unset>}"

# Change 1: align the Proxmox VM name to the ProxmoxMachine object name
# (the single Proxmox-side write).
if [ "$cur_name" = "$PROXMOX_MACHINE" ]; then
  log "VM name already matches the ProxmoxMachine name ('$PROXMOX_MACHINE'); skipping rename"
else
  log "Renaming Proxmox VM $PROXMOX_VM_ID: '$cur_name' -> '$PROXMOX_MACHINE'"
  px set "$PROXMOX_VM_ID" name "$PROXMOX_MACHINE"
  log "  now: $(px config "$PROXMOX_VM_ID" | awk '/^name:/{print $2}')"
fi

# Change 2: point the ProxmoxMachine at the VM (local kubectl patch only).
log "Setting spec.virtualMachineID=$PROXMOX_VM_ID on ProxmoxMachine/$PROXMOX_MACHINE"
kubectl patch "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" --type merge -p \
  "$(jq -n --argjson vmid "$PROXMOX_VM_ID" '{spec:{virtualMachineID:$vmid}}')"

log "Done. The provider will reconcile; verify with (no changes are made by these):"
log "  kubectl get proxmoxmachine/$PROXMOX_MACHINE -n $NAMESPACE -o yaml   # status.vmStatus: running, status.providerID: proxmox://$bios_uuid"
log "  kubectl get machine -n $NAMESPACE -o yaml | jq '.items[] | select(.spec.infrastructureRef.name==\"$PROXMOX_MACHINE\") | {name:.metadata.name, ready:.status.ready, nodeRef:.status.nodeRef, providerID:.spec.providerID}'"
log "  kubectl get taloscontrolplane -n $NAMESPACE   # expect Resized 1/1, no scaling"
log "  talosctl -n <node-ip> --nodes <node-ip> version   # the restored node is the control-plane member"
