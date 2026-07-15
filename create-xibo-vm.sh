#!/bin/bash
#
# Create Xibo VM - Proxmox VE
# Creates a clean Ubuntu 24.04 VM ready for Xibo installation
#
# Run this script on the Proxmox host
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

msg_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
msg_ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
msg_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
msg_error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}     Create Xibo VM (Proxmox VE)       ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root on the Proxmox host."
fi

if ! command -v qm &> /dev/null; then
    msg_error "This script must be run on a Proxmox VE host."
fi

# Ask for VM configuration
read -p "VM ID (e.g. 200): " VMID
read -p "VM Name / Hostname (e.g. xibo-server): " VMNAME
read -p "CPU Cores (default 4): " CPU_CORES
CPU_CORES=${CPU_CORES:-4}
read -p "RAM in MB (default 8192): " RAM
RAM=${RAM:-8192}
read -p "Disk Size in GB (default 64): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-64}
read -p "Storage (e.g. local-lvm, local-zfs): " STORAGE
read -p "Network Bridge (default vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}
read -p "Username for the VM (default ubuntu): " VM_USER
VM_USER=${VM_USER:-ubuntu}
read -sp "Password for the VM user: " VM_PASS
echo ""

if [[ -z "$VMID" || -z "$VMNAME" || -z "$STORAGE" || -z "$VM_PASS" ]]; then
    msg_error "VM ID, Name, Storage and Password are required."
fi

if qm list | awk '{print $1}' | grep -q "^${VMID}$"; then
    msg_error "VM ID $VMID already exists."
fi

# Network configuration
echo ""
read -p "Network configuration? [dhcp/static] (default: dhcp): " NET_TYPE
NET_TYPE=${NET_TYPE:-dhcp}

IPCONFIG=""

if [[ "$NET_TYPE" == "static" ]]; then
    echo ""
    read -p "Enter IP address with CIDR (e.g. 192.168.1.50/24): " IP_CIDR
    read -p "Enter Gateway (e.g. 192.168.1.1): " GATEWAY
    read -p "Enter DNS servers (default: 8.8.8.8,1.1.1.1): " DNS
    DNS=${DNS:-8.8.8.8,1.1.1.1}

    IPCONFIG="ip=${IP_CIDR},gw=${GATEWAY}"
fi

msg_info "Creating VM ${VMID} (${VMNAME})..."

qm create "$VMID" \
    --name "$VMNAME" \
    --cores "$CPU_CORES" \
    --memory "$RAM" \
    --net0 "virtio,bridge=${BRIDGE}" \
    --scsihw virtio-scsi-pci \
    --scsi0 "${STORAGE}:${DISK_SIZE},discard=on" \
    --ostype l26 \
    --agent 1

qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
qm set "$VMID" --boot order=scsi0

# Apply IP configuration if static
if [[ "$NET_TYPE" == "static" ]]; then
    qm set "$VMID" --ipconfig0 "$IPCONFIG"
fi

# Cloud-init user
qm set "$VMID" --ciuser "$VM_USER"
qm set "$VMID" --cipassword "$VM_PASS"

msg_info "Starting VM ${VMID}..."
qm start "$VMID"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   VM Creation completed!              ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}VM Details:${NC}"
echo "  VM ID      : $VMID"
echo "  Name       : $VMNAME"
echo "  User       : $VM_USER"
echo "  Network    : $NET_TYPE"
if [[ "$NET_TYPE" == "static" ]]; then
    echo "  IP         : $IP_CIDR"
    echo "  Gateway    : $GATEWAY"
fi
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Wait for the VM to fully boot"
echo "2. SSH into the VM using the username and password you set"
echo "3. Run the Xibo installer inside the VM"
echo ""
msg_ok "VM $VMID ($VMNAME) has been created and started."
