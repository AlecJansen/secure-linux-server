#!/bin/bash

# setup.sh - Secure Linux Server Setup Script

set -euo pipefail
trap 'echo -e "\033[0;31m[!] Error on line $LINENO. Exiting.\033[0m"' ERR

# Logging
LOG_FILE="$HOME/secure-linux-server/setup-$(date +%F).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo -e "\033[0;31m[!] Please run this script as root or with sudo.\033[0m"
  exit 1
fi

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ASCII Logo
echo -e "${BLUE}"
echo "   ____                  _             _                "
echo "  / ___|  ___ _ ____   _(_) ___ ___   / \\   ___ ___ ___ "
echo "  \\___ \\ / _ \\ '__\\ \\ / / |/ __/ _ \\ / _ \\ / __/ __/ _ \\" 
echo "   ___) |  __/ |   \\ V /| | (_|  __// ___ \\ (_| (_|  __/"
echo "  |____/ \\___|_|    \\_/ |_|\\___\\___/_/   \\_\\___\\___\\___|"
echo -e "${NC}"
echo -e "${YELLOW}Welcome to the Secure Linux Server Setup Script!${NC}"
echo

# Check for internet connectivity
if ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
  echo -e "${RED}[!] No internet connection detected. Aborting.${NC}"
  exit 1
fi

read -p "[*] Proceed with system update and upgrade? (y/n): " update_choice
if [[ "$update_choice" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}[*] Updating system...${NC}"
  apt update && apt upgrade -y
fi

# Install essential tools
tools=(ufw fail2ban lynis rkhunter clamav chkrootkit unattended-upgrades mailutils msmtp)
echo -e "${BLUE}[*] Installing required packages...${NC}"
apt install -y "${tools[@]}"

# UFW Setup
echo -e "${BLUE}[*] Configuring UFW...${NC}"
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw --force enable

# Fail2Ban Setup
echo -e "${BLUE}[*] Enabling Fail2Ban...${NC}"
systemctl enable --now fail2ban

# Optional jail.local copy
if [[ -f "$SCRIPT_DIR/fail2ban/jail.local" ]]; then
  echo -e "${BLUE}[*] Copying jail.local config...${NC}"
  cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
  systemctl restart fail2ban
fi

# RKHunter Setup
echo -e "${BLUE}[*] Updating RKHunter properties database...${NC}"
rkhunter --propupd -q || true

# ClamAV DB Update
echo -e "${BLUE}[*] Updating ClamAV virus database...${NC}"
freshclam || true

# Ensure log directory exists
mkdir -p "$HOME/secure-linux-server/logs"

# Setup notify.sh without overwriting existing one
NOTIFY_SRC="$SCRIPT_DIR/alerts/scripts/notify.sh"
NOTIFY_DEST="$HOME/secure-linux-server/alerts/scripts/notify.sh"

if [[ -f "$NOTIFY_DEST" ]]; then
  echo -e "${YELLOW}[!] notify.sh already exists, skipping copy.${NC}"
else
  mkdir -p "$(dirname "$NOTIFY_DEST")"
  cp "$NOTIFY_SRC" "$NOTIFY_DEST"
  chmod +x "$NOTIFY_DEST"
  echo -e "${GREEN}[+] notify.sh installed to $NOTIFY_DEST${NC}"
fi

echo -e "\n${GREEN}[✓] Setup complete.${NC}"
