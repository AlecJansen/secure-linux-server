#!/bin/bash

# setup.sh - Interactive Secure Linux Server Setup

set -euo pipefail
trap 'echo -e "\033[0;31m[!] Error on line $LINENO. Exiting.\033[0m"' ERR

# Logging
LOG_FILE="$HOME/secure-linux-server/setup-$(date +%F).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"

# Ensure root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[!] Please run as root or with sudo.${NC}"
  exit 1
fi

# Check apt-get
if ! command -v apt-get &> /dev/null; then
  echo -e "${RED}[!] apt-get is missing. This script requires a Debian-based system.${NC}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ASCII Header
echo -e "${BLUE}"
echo "   ____                  _             _                "
echo "  / ___|  ___ _ ____   _(_) ___ ___   / \\   ___ ___ ___ "
echo "  \\___ \\ / _ \\ '__\\ \\ / / |/ __/ _ \\ / _ \\ / __/ __/ _ \\"
echo "   ___) |  __/ |   \\ V /| | (_|  __// ___ \\ (_| (_|  __/"
echo "  |____/ \\___|_|    \\_/ |_|\\___\\___/_/   \\_\\___\\___\\___|"
echo -e "${NC}"
echo -e "${YELLOW}Welcome to the Secure Linux Server Setup Script!${NC}"
echo

# Connectivity check
if ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
  echo -e "${RED}[!] No internet connection detected. Aborting.${NC}"
  exit 1
fi

# Feature toggles
declare -A summary
summary["System Upgrade"]="Skipped"
summary["Firewall"]="Skipped"
summary["Fail2Ban"]="Skipped"
summary["RKHunter DB Init"]="Skipped"
summary["Clamd"]="Not Enabled"
summary["clamdscan Test"]="Not Run"
summary["Lynis Audit"]="Skipped"
summary["notify.sh"]="Not Installed"

read -p "[*] Proceed with system update and upgrade? (y/n): " upgrade
if [[ "$upgrade" =~ ^[Yy]$ ]]; then
  apt-get update && apt-get upgrade -y
  summary["System Upgrade"]="✓"
fi

# Install essentials
tools=(ufw fail2ban lynis rkhunter clamav chkrootkit unattended-upgrades mailutils msmtp)
echo -e "${BLUE}[*] Installing required packages...${NC}"
apt-get install -y "${tools[@]}"

# UFW
read -p "[*] Enable UFW with SSH allowed and default rules? (y/n): " ufw_choice
if [[ "$ufw_choice" =~ ^[Yy]$ ]]; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw --force enable
  summary["Firewall"]="✓"
fi

# Fail2Ban
read -p "[*] Enable Fail2Ban for SSH protection? (y/n): " f2b
if [[ "$f2b" =~ ^[Yy]$ ]]; then
  systemctl enable --now fail2ban
  summary["Fail2Ban"]="✓"
fi

# Optional jail.local
if [[ -f "$SCRIPT_DIR/fail2ban/jail.local" ]]; then
  echo -e "${BLUE}[*] Copying jail.local config...${NC}"
  cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
  systemctl restart fail2ban
fi

# RKHunter
read -p "[*] Initialize rkhunter properties DB now? (y/n): " rkh
if [[ "$rkh" =~ ^[Yy]$ ]]; then
  rkhunter --propupd -q || true
  summary["RKHunter DB Init"]="✓"
fi

# ClamAV DB
echo -e "${BLUE}[*] Updating ClamAV virus database...${NC}"
sudo -u clamav freshclam || true

# clamd setup
read -p "[*] Enable clamd daemon and socket? (y/n): " enable_clamd
if [[ "$enable_clamd" =~ ^[Yy]$ ]]; then
  chown -R clamav:clamav /var/lib/clamav /var/log/clamav
  systemctl unmask clamav-daemon.socket
  systemctl unmask clamav-daemon.service
  systemctl enable --now clamav-daemon
  sleep 2
  if [[ -S /var/run/clamav/clamd.ctl ]]; then
    echo -e "${GREEN}[✓] clamd is running and socket is available.${NC}"
    summary["Clamd"]="✓"
  else
    echo -e "${RED}[!] clamd socket not found. Check service status.${NC}"
  fi
fi

# clamdscan test
read -p "[*] Run test scan using clamdscan? (y/n): " testscan
if [[ "$testscan" =~ ^[Yy]$ ]]; then
  if clamdscan --fdpass /etc/hostname &>/dev/null; then
    echo -e "${GREEN}[✓] clamdscan test succeeded.${NC}"
    summary["clamdscan Test"]="✓"
  else
    echo -e "${RED}[!] clamdscan test failed.${NC}"
  fi
fi

# Lynis system audit
read -p "[*] Run Lynis system audit now? (y/n): " lynis_choice
if [[ "$lynis_choice" =~ ^[Yy]$ ]]; then
  echo -e "${BLUE}[*] Running Lynis audit...${NC}"
  LYNIS_OUT="$HOME/secure-linux-server/logs/lynis-report.txt"
  mkdir -p "$(dirname "$LYNIS_OUT")"
  lynis audit system --quiet > "$LYNIS_OUT" || true
  echo -e "${GREEN}[✓] Lynis report saved to: $LYNIS_OUT${NC}"
  summary["Lynis Audit"]="✓"
else
  summary["Lynis Audit"]="Skipped"
fi

# notify.sh prompt
read -p "[*] Install notify.sh to default location? (y/n): " install_notify
if [[ "$install_notify" =~ ^[Yy]$ ]]; then
  NOTIFY_SRC="$SCRIPT_DIR/alerts/scripts/notify.sh"
  NOTIFY_DEST="$HOME/secure-linux-server/alerts/scripts/notify.sh"
  if [[ -f "$NOTIFY_DEST" ]]; then
    echo -e "${YELLOW}[!] notify.sh already exists, skipping copy.${NC}"
  else
    mkdir -p "$(dirname "$NOTIFY_DEST")"
    cp "$NOTIFY_SRC" "$NOTIFY_DEST"
    chmod +x "$NOTIFY_DEST"
    echo -e "${GREEN}[+] notify.sh installed to $NOTIFY_DEST${NC}"
    summary["notify.sh"]="✓"
  fi
fi

# Final Recap
echo -e "\n${BLUE}========= Setup Summary =========${NC}"
for key in "${!summary[@]}"; do
  status="${summary[$key]}"
  printf "%-20s %s\n" "$key:" "$status"
done
echo -e "${GREEN}\n[✓] Setup complete.${NC}"
