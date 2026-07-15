#!/bin/bash
#
# Xibo Self-Hosted Docker Installer
# For Ubuntu 24.04 (Proxmox VE VMs or bare metal)
# Includes MySQL 8.4 compatibility fixes for Xibo v4
#
# Run this script inside the Ubuntu VM
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
echo -e "${BLUE}   Xibo Self-Hosted Docker Installer   ${NC}"
echo -e "${BLUE}          Ubuntu 24.04                 ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if [[ $EUID -ne 0 ]]; then
    msg_error "This script must be run as root or with sudo."
fi

# Ask for passwords
echo -e "${YELLOW}Please enter the required passwords:${NC}"
read -sp "MySQL password for user 'cms': " MYSQL_PASS
echo ""
read -sp "Xibo admin password (for after first login): " ADMIN_PASS
echo ""
echo ""

if [[ -z "$MYSQL_PASS" || -z "$ADMIN_PASS" ]]; then
    msg_error "Passwords cannot be empty."
fi

# ====================== SYSTEM UPDATE & ESSENTIAL PACKAGES ======================
msg_info "Updating system and installing essential packages..."

apt update && apt upgrade -y -qq

apt install -y \
    qemu-guest-agent \
    chrony \
    htop \
    nano \
    pico \
    rsync \
    openssh-server

# Enable and start qemu-guest-agent
systemctl enable --now qemu-guest-agent

msg_ok "Essential packages installed."

# ====================== DOCKER INSTALLATION ======================
msg_info "Installing Docker and prerequisites..."

apt install -y ca-certificates curl gnupg lsb-release unzip

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update -qq
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if [[ -n "${SUDO_USER:-}" ]]; then
    usermod -aG docker "$SUDO_USER"
    msg_warn "User '$SUDO_USER' added to docker group. Log out and back in after installation."
fi

# ====================== XIBO INSTALLATION ======================
msg_info "Downloading latest Xibo Docker package..."

mkdir -p /opt/xibo
cd /opt/xibo

curl -L -o xibo-docker.tar.gz https://xibosignage.com/api/downloads/cms
tar -xzf xibo-docker.tar.gz

INSTALL_DIR=$(find . -maxdepth 1 -type d -name "xibo-docker-*" | head -n 1)
cd "$INSTALL_DIR"

msg_info "Creating optimized docker-compose.yml..."

cat > docker-compose.yml << 'COMPOSE_EOF'
version: "3.8"

services:
  cms-db:
    image: mysql:8.4
    command: --mysql-native-password=ON
    volumes:
      - "./shared/db:/var/lib/mysql:Z"
    env_file: config.env
    restart: always
    mem_limit: 1g

  cms-xmr:
    image: ghcr.io/xibosignage/xibo-xmr:1.3
    ports:
      - "9505:9505"
    restart: always
    mem_limit: 256m
    env_file: config.env

  cms-web:
    image: ghcr.io/xibosignage/xibo-cms:release-4.4.4
    volumes:
      - "./shared/cms/custom:/var/www/cms/custom:Z"
      - "./shared/backup:/var/www/backup:Z"
      - "./shared/cms/web/theme/custom:/var/www/cms/web/theme/custom:Z"
      - "./shared/cms/library:/var/www/cms/library:Z"
      - "./shared/cms/web/userscripts:/var/www/cms/web/userscripts:Z"
      - "./shared/cms/ca-certs:/var/www/cms/ca-certs:Z"
    ports:
      - "80:80"
    restart: always
    mem_limit: 1g
    env_file: config.env
    environment:
      - MYSQL_HOST=cms-db
      - XMR_HOST=cms-xmr
      - CMS_USE_MEMCACHED=true
      - MEMCACHED_HOST=cms-memcached

  cms-memcached:
    image: memcached:alpine
    command: memcached -m 15
    restart: always
    mem_limit: 100M

  cms-quickchart:
    image: ianw/quickchart
    restart: always
COMPOSE_EOF

msg_info "Creating config.env..."

cat > config.env << EOF
MYSQL_ROOT_PASSWORD=${MYSQL_PASS}
MYSQL_PASSWORD=${MYSQL_PASS}
MYSQL_USER=cms
MYSQL_DATABASE=cms
EOF

msg_info "Cleaning previous database data..."
rm -rf ./shared/db 2>/dev/null || true

msg_info "Starting Xibo containers..."
docker compose up -d

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Xibo installation completed!         ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "1. Wait 60–90 seconds for MySQL to fully initialize."
echo ""
echo "2. Open your browser and go to:"
echo "   http://$(hostname -I | awk '{print $1}')"
echo ""
echo "3. Login with:"
echo "   Username : xibo_admin"
echo "   Password : password"
echo ""
echo "4. **Change the admin password immediately** to:"
echo "   ${ADMIN_PASS}"
echo ""
echo -e "${YELLOW}5. Set XMR Public Address:${NC}"
echo "   Go to: Administration → Settings → Displays"
echo "   Set XMR Public Address to:"
echo "   tcp://$(hostname -I | awk '{print $1}'):9505"
echo ""
echo -e "${GREEN}Your Xibo CMS is now running at: http://$(hostname -I | awk '{print $1}')${NC}"
echo ""
msg_ok "Installation finished successfully!"
