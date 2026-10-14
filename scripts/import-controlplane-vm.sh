#!/bin/bash

set -euo pipefail

# import-controlplane-vm.sh
#
# Adopt a Proxmox VM that was recreated by hand (e.g. restored from a Proxmox
# backup) back into an existing, already-provisioned Cluster API ProxmoxMachine.
#
# This makes the TalosControlPlane stop provisioning a replacement VM and lets
# you keep operating the node manually with talosctl. See the "Runbooks" section
# of the README for the full explanation of what this does and why.
#
# It performs the two manual inputs the provider's adoption path requires:
#   1. Rename the Proxmox VM so its `name` matches the ProxmoxMachine object
#      name (the provider's FindVM adoption path looks the VM up by ID and then
#      requires the name to match exactly).
#   2. Repoint the ProxmoxMachine at the VM by setting spec.virtualMachineID and
#      spec.providerID (the VM's real SMBIOS UUID).
#
# Safety:
#   * It refuses to run against a ProxmoxMachine that is not already provisioned
#     (no spec.providerID), because adopting a mid-provisioning machine could
#     re-trigger cloning.
#   * It never destroys the VM it is adopting. Destroying the redundant
#     replacement VM is opt-in via DESTROY_REPLACEMENT_VMID, and the script
#     refuses if that equals PROXMOX_VM_ID.

PROXMOX_VM_ID=${PROXMOX_VM_ID:-}
PROXMOX_MACHINE=${PROXMOX_MACHINE:-}
NAMESPACE=${NAMESPACE:-homelab}
MACHINE=${MACHINE:-}
DESTROY_REPLACEMENT_VMID=${DESTROY_REPLACEMENT_VMID:-}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-120}

log() { echo "[import-controlplane-vm] $*"; }
die() { echo "[import-controlplane-vm] ERROR: $*" >&2; exit 1; }

[ -n "$PROXMOX_VM_ID" ]   || die "PROXMOX_VM_ID is mandatory"
[ -n "$PROXMOX_MACHINE" ] || die "PROXMOX_MACHINE is mandatory"
[[ "$PROXMOX_VM_ID" =~ ^[0-9]+$ ]] || die "PROXMOX_VM_ID must be a numeric VMID (got '$PROXMOX_VM_ID')"
command -v qm      &>/dev/null || die "qm not found in PATH"
command -v kubectl &>/dev/null || die "kubectl not found in PATH"
command -v jq      &>/dev/null || die "jq not found in PATH"

log "Checking prerequisites (namespace=$NAMESPACE)"

kubectl get "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" >/dev/null 2>&1 \
  || die "ProxmoxMachine/$PROXMOX_MACHINE not found in namespace $NAMESPACE"

pm_data=$(kubectl get "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" -o json)
cur_provider_id=$(printf '%s' "$pm_data" | jq -r '.spec.providerID // empty')
cur_vm_id=$(printf '%s' "$pm_data" | jq -r '.spec.virtualMachineID // empty')

[ -n "$cur_provider_id" ] \
  || die "ProxmoxMachine/$PROXMOX_MACHINE has no spec.providerID yet; it does not look provisioned. This script only adopts already-provisioned machines. Refusing."

qm config "$PROXMOX_VM_ID" >/dev/null 2>&1 || die "VM $PROXMOX_VM_ID not found via qm"

bios_uuid=$(qm config "$PROXMOX_VM_ID" \
  | grep -oE 'uuid=[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}' | head -n1 | cut -d= -f2)
[ -n "$bios_uuid" ] || die "could not read the smbios1 uuid from VM $PROXMOX_VM_ID"
new_provider_id="proxmox://$bios_uuid"

cur_name=$(qm config "$PROXMOX_VM_ID" | awk '/^name:/{print $2}')
log "VM $PROXMOX_VM_ID: name='${cur_name:-<unset>}' smbios1=$bios_uuid"
log "ProxmoxMachine/$PROXMOX_MACHINE: providerID=$cur_provider_id virtualMachineID=${cur_vm_id:-<unset>}"

# Step 1: align the Proxmox VM name to the ProxmoxMachine object name.
if [ "$cur_name" = "$PROXMOX_MACHINE" ]; then
  log "VM name already matches the ProxmoxMachine name ('$PROXMOX_MACHINE'); skipping rename"
else
  log "Renaming Proxmox VM $PROXMOX_VM_ID: '$cur_name' -> '$PROXMOX_MACHINE'"
  qm set "$PROXMOX_VM_ID" name "$PROXMOX_MACHINE"
  log "  now: $(qm config "$PROXMOX_VM_ID" | awk '/^name:/{print $2}')"
fi

# Step 2: repoint the ProxmoxMachine at the VM.
log "Repointing ProxmoxMachine/$PROXMOX_MACHINE at VMID $PROXMOX_VM_ID ($new_provider_id)"
kubectl patch "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" --type merge -p \
  "$(jq -n --argjson vmid "$PROXMOX_VM_ID" --arg pid "$new_provider_id" \
       '{spec:{virtualMachineID:$vmid, providerID:$pid}}')"

# Step 3: wait for the adoption to converge (VM found + running).
log "Waiting up to ${WAIT_TIMEOUT}s for the machine to adopt VM $PROXMOX_VM_ID"
deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
ready=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  vm_status=$(kubectl get "proxmoxmachine/$PROXMOX_MACHINE" -n "$NAMESPACE" -o jsonpath='{.status.vmStatus}')
  if [ "$vm_status" = "running" ]; then
    ready=1
    break
  fi
  log "  ... vmStatus=${vm_status:-<unset>} (want 'running')"
  sleep 5
done
[ "$ready" = "1" ] || die "the machine did not report vmStatus=running within ${WAIT_TIMEOUT}s; check the ProxmoxMachine status and controller logs"
log "Adoption converged: ProxmoxMachine/$PROXMOX_MACHINE vmStatus=running"

# Step 4 (best effort): verify the owning CAPI Machine.
if [ -z "$MACHINE" ]; then
  MACHINE=$(kubectl get machine -n "$NAMESPACE" -o json \
    | jq -r --arg pm "$PROXMOX_MACHINE" '.items[] | select(.spec.infrastructureRef.name==$pm) | .metadata.name' \
    | head -n1)
fi

if [ -n "$MACHINE" ]; then
  machine_ready=$(kubectl get machine "$MACHINE" -n "$NAMESPACE" -o jsonpath='{.status.ready}')
  node_ref=$(kubectl get machine "$MACHINE" -n "$NAMESPACE" -o jsonpath='{.status.nodeRef.name}')
  machine_provider_id=$(kubectl get machine "$MACHINE" -n "$NAMESPACE" -o jsonpath='{.spec.providerID}')
  log "CAPI Machine/$MACHINE: ready=${machine_ready:-<unset>} nodeRef=${node_ref:-<unset>} providerID=${machine_provider_id:-<unset>}"
  [ "$machine_provider_id" = "$new_provider_id" ] \
    || log "  NOTE: Machine providerID does not match the VM uuid yet; the controller may still be reconciling"
else
  log "WARNING: could not determine the owning CAPI Machine for verification (set MACHINE=<name> to force)"
fi

# Step 5 (opt-in): destroy the redundant replacement VM.
if [ -n "$DESTROY_REPLACEMENT_VMID" ]; then
  [[ "$DESTROY_REPLACEMENT_VMID" =~ ^[0-9]+$ ]] || die "DESTROY_REPLACEMENT_VMID must be a numeric VMID"
  [ "$DESTROY_REPLACEMENT_VMID" != "$PROXMOX_VM_ID" ] \
    || die "DESTROY_REPLACEMENT_VMID must differ from PROXMOX_VM_ID (never destroy the adopted VM)"
  log "Destroying redundant replacement VM $DESTROY_REPLACEMENT_VMID"
  qm destroy "$DESTROY_REPLACEMENT_VMID"
else
  log "Next (manual, after the adoption is verified stable): destroy the redundant replacement VM you no longer need:"
  log "  qm status <replacement-vmid>   # confirm it is NOT VM $PROXMOX_VM_ID"
  log "  qm destroy <replacement-vmid>"
fi

log "Done. Verify the node is the control-plane member: talosctl -n <node-ip> --nodes <node-ip> version"
