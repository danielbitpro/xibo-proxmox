# Xibo on Proxmox VE - Deployment Scripts

Easy deployment of Xibo Digital Signage on Proxmox VE using two scripts:

- `create-xibo-vm.sh` — Creates a clean Ubuntu 24.04 VM on Proxmox
- `install-xibo.sh` — Installs Xibo inside the Ubuntu VM (with MySQL 8.4 fixes)

## Quick Start (Recommended)

### 1. Create the VM (Run on Proxmox Host)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielbitpro/xibo-proxmox/main/create-xibo-vm.sh)"
```

### 2. Install Xibo (Run on the new VM)

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielbitpro/xibo-proxmox/main/install-xibo.sh)"
```
