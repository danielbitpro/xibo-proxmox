#!/bin/bash
#
# Create Xibo VM - Proxmox VE
# Creates an Ubuntu 24.04 VM using cloud image + cloud-init
#

set -euo pipefail

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

# VM Configuration
read -p "VM ID (e.g. 200): " VMID
read -p "VM Name (e.g. xibo-server): " VMNAME
read -p "CPU Cores (default 4): " CPU_CORES; CPU_CORES=${CPU_CORES:-4}
read -p "RAM in MB (default 8192): " RAM; RAM=${RAM:-8192}
read -p "Disk Size in GB (default 64): " DISK_SIZE; DISK_SIZE=${DISK_SIZE:-64}
read -p "Storage (e.g. local-lvm): " STORAGE
read -p "Network Bridge (default vmbr0): " BRIDGE; BRIDGE=${BRIDGE:-vmbr0}
read -p "Username (default ubuntu): " VM_USER; VM_USER=${VM_USER:-ubuntu}
read -sp "Password: " VM_PASS; echo ""

if [[ -z "$VMID" || -z "$VMNAME" || -z "$STORAGE" || -z "$VM_PASS" ]]; then
    msg_error "Missing required fields."
fi

if qm list | awk '{print $1}' | grep -q "^$VMID$"; then
    msg_error "VM ID $VMID already exists."
fi

# Network
echo ""
read -p "Network? [dhcp/static] (default: dhcp): " NET_TYPE; NET_TYPE=${NET_TYPE:-dhcp}

IPCONFIG=""
if [[ "$NET_TYPE" == "static" ]]; then
    read -p "IP/CIDR (e.g. 192.168.1.50/24): " IP_CIDR
    read -p "Gateway: " GATEWAY
    IPCONFIG="ip=${IP_CIDR},gw=${GATEWAY}"
fi

# Download Cloud Image
CLOUD_IMAGE="ubuntu-24.04-server-cloudimg-amd64.img"
TEMPLATE_DIR="/var/lib/vz/template/iso"
mkdir -p "$TEMPLATE_DIR"

if [[ ! -f "$TEMPLATE_DIR/$CLOUD_IMAGE" ]]; then
    msg_info "Downloading Ubuntu 24.04 cloud image..."
    wget -q --show-progress -O "$TEMPLATE_DIR/$CLOUD_IMAGE" \
    https://cloud-images.ubuntu.com/releases/24.04/release/$CLOUD_IMAGE
fi

# Create VM
msg_info "Creating VM $VMID ($VMNAME)..."
qm create "$VMID" \
    --name "$VMNAME" \
    --cores "$CPU_CORES" \
    --memory "$RAM" \
    --net0 "virtio,bridge=$BRIDGE" \
    --scsihw virtio-scsi-pci \
    --ostype l26 \
    --agent 1

# Import cloud image
qm importdisk "$VMID" "$TEMPLATE_DIR/$CLOUD_IMAGE" "$STORAGE"
qm set "$VMID" --scsi0 "$STORAGE:vm-$VMID-disk-0,discard=on"
qm set "$VMID" --boot order=scsi0
qm set "$VMID" --ide2 "$STORAGE:cloudinit"

if [[ "$NET_TYPE" == "static" ]]; then
    qm set "$VMID" --ipconfig0 "$IPCONFIG"
fi

# Cloud-init configuration
qm set "$VMID" --ciuser "$VM_USER"
qm set "$VMID" --cipassword "$VM_PASS"

# Enable SSH password authentication
qm set "$VMID" --ci-custom user=cloud-init:ssh_pwauth=true

# Start VM
msg_info "Starting VM..."
qm start "$VMID"

echo ""
echo -e "${GREEN}VM $VMID ($VMNAME) created and started successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for cloud-init to finish"
echo "2. SSH into the VM using username '$VM_USER' and the password you set"
echo "3. Run the Xibo installer inside the VM"
