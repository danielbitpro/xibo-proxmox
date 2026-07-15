#!/bin/bash
#
# Create Xibo VM - Proxmox VE
# Creates an Ubuntu 24.04 VM using cloud image + cloud-init
#
# Run this on the Proxmox host
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

# ====================== VM CONFIG ======================
read -p "VM ID (e.g. 200): " VMID
read -p "VM Name (e.g. xibo-server): " VMNAME
read -p "CPU Cores (default 4): " CPU_CORES
CPU_CORES=${CPU_CORES:-4}
read -p "RAM in MB (default 8192): " RAM
RAM=${RAM:-8192}
read -p "Disk Size in GB (default 64): " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-64}
read -p "Storage (e.g. local-lvm, local-zfs): " STORAGE
read -p "Network Bridge (default vmbr0): " BRIDGE
BRIDGE=${BRIDGE:-vmbr0}
read -p "Username (default ubuntu): " VM_USER
VM_USER=${VM_USER:-ubuntu}
read -sp "Password for the VM user: " VM_PASS
echo ""

if [[ -z "$VMID" || -z "$VMNAME" || -z "$STORAGE" || -z "$VM_PASS" ]]; then
    msg_error "Required fields are missing."
fi

if qm list | awk '{print $1}' | grep -q "^${VMID}$"; then
    msg_error "VM ID $VMID already exists."
fi

# ====================== NETWORK ======================
echo ""
read -p "Network: DHCP or Static? [dhcp/static] (default: dhcp): " NET_TYPE
NET_TYPE=${NET_TYPE:-dhcp}

IPCONFIG=""

if [[ "$NET_TYPE" == "static" ]]; then
    read -p "IP Address with CIDR (e.g. 192.168.1.50/24): " IP_CIDR
    read -p "Gateway (e.g. 192.168.1.1): " GATEWAY
    read -p "DNS servers (default: 8.8.8.8,1.1.1.1): " DNS_SERVERS
    DNS_SERVERS=${DNS_SERVERS:-8.8.8.8,1.1.1.1}

    IPCONFIG="ip=${IP_CIDR},gw=${GATEWAY}"
fi

# ====================== CLOUD IMAGE ======================
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
CLOUD_IMAGE_NAME="ubuntu-24.04-server-cloudimg-amd64.img"
TEMPLATE_DIR="/var/lib/vz/template/iso"

msg_info "Downloading Ubuntu 24.04 cloud image (if not present)..."
mkdir -p "$TEMPLATE_DIR"
if [[ ! -f "$TEMPLATE_DIR/$CLOUD_IMAGE_NAME" ]]; then
    wget -q --show-progress -O "$TEMPLATE_DIR/$CLOUD_IMAGE_NAME" "$CLOUD_IMAGE_URL"
else
    msg_info "Cloud image already exists. Skipping download."
fi

# ====================== CREATE VM ======================
msg_info "Creating VM $VMID ($VMNAME)..."

qm create "$VMID" \
    --name "$VMNAME" \
    --cores "$CPU_CORES" \
    --memory "$RAM" \
    --net0 "virtio,bridge=${BRIDGE}" \
    --scsihw virtio-scsi-pci \
    --ostype l26 \
    --agent 1

# Import cloud image as disk
msg_info "Importing cloud image as disk..."
qm importdisk "$VMID" "$TEMPLATE_DIR/$CLOUD_IMAGE_NAME" "$STORAGE"

# Attach imported disk as scsi0 and make it bootable
qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0,discard=on"
qm set "$VMID" --boot order=scsi0

# Add cloud-init drive
qm set "$VMID" --ide2 "$STORAGE:cloudinit"

# Apply IP config if static
if [[ "$NET_TYPE" == "static" && -n "$IPCONFIG" ]]; then
    qm set "$VMID" --ipconfig0 "$IPCONFIG"
fi

# Cloud-init user settings
qm set "$VMID" --ciuser "$VM_USER"
qm set "$VMID" --cipassword "$VM_PASS"

# Start the VM
msg_info "Starting VM $VMID..."
qm start "$VMID"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   VM created and started successfully! ${NC}"
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
echo "1. Wait 1-2 minutes for cloud-init to finish setup"
echo "2. Find the VM IP (check Proxmox console or DHCP server)"
echo "3. SSH into the VM and run the Xibo installer"
echo ""
msg_ok "VM is ready."
