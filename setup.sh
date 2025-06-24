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
CHECK="✓"

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

# Declare summary globally
declare -gA summary

# Utility functions
prompt_yes_no() {
  local prompt="$1"
  local choice
  read -rp "$prompt (Y/n): " choice
  [[ -z "$choice" || "$choice" =~ ^[Yy]$ ]]
}

init_summary() {
  summary=(
    ["System Upgrade"]="Skipped"
    ["Firewall"]="Skipped"
    ["Fail2Ban"]="Skipped"
    ["RKHunter DB Init"]="Skipped"
    ["Clamd"]="Not Enabled"
    ["MTA Setup"]="Not Configured"
    ["Lynis Audit"]="Skipped"
    ["notify.sh"]="Not Installed"
    ["Email Config"]="Not Set"
    ["SSH Root Login"]="Not Modified"
  )
}

validate_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# ASCII Header
echo -e "${BLUE}"
echo "  ____                  _             _            "
echo " / ___|  ___ _ ____   _(_) ___ ___   / \\   ___ ___ "
echo " \\___ \\ / _ \\ '__\\ \\ / / |/ __/ _ \\ / _ \\ / __/ _ \\" 
echo "  ___) |  __/ |   \\ V /| | (_|  __// ___ \\ (_|  __/"
echo " |____/ \\___|_|    \\_/ |_|\\___\\___/_/   \\_\\___\\___/"
echo -e "${NC}"
echo -e "${YELLOW}Welcome to the Secure Linux Server Setup Script!${NC}"
echo

# Connectivity check
if ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
  echo -e "${RED}[!] No internet connection detected. Aborting.${NC}"
  exit 1
fi

# Initialize summary
init_summary

# Upgrade system
if prompt_yes_no "[*] Proceed with system update and upgrade?"; then
  apt-get update && apt-get upgrade -y
  summary["System Upgrade"]="$CHECK"
fi

# Email config path
CONFIG_DIR="$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/secure-linux-server/config"
CONFIG_FILE="$CONFIG_DIR/alert.conf"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

# Email input
echo -e "${BLUE}[*] Configuring alert email(s)...${NC}"
EMAIL_VALID=0
for attempt in {1..3}; do
  read -rp "Enter the email to receive alerts: " USER_EMAIL
  if validate_email "$USER_EMAIL"; then
    EMAIL_VALID=1
    break
  else
    echo -e "${YELLOW}[!] Invalid email format. Please try again.${NC}"
  fi
done

if [[ "$EMAIL_VALID" -eq 1 ]]; then
  touch "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  grep -Ev '^$' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  if ! grep -Fxq "EMAIL=\"$USER_EMAIL\"" "$CONFIG_FILE"; then
    echo "EMAIL=\"$USER_EMAIL\"" >> "$CONFIG_FILE"
    echo -e "${GREEN}[$CHECK] Email added to $CONFIG_FILE${NC}"
  else
    echo -e "${YELLOW}[!] Email already present in $CONFIG_FILE${NC}"
  fi
  summary["Email Config"]="$USER_EMAIL"
else
  echo -e "${RED}[!] No valid email entered after 3 attempts. Skipping email config.${NC}"
fi

# Install tools
tools=(ufw fail2ban lynis rkhunter clamav clamav-daemon chkrootkit unattended-upgrades mailutils msmtp)
echo -e "${BLUE}[*] Installing required packages...${NC}"
to_install=()
for pkg in "${tools[@]}"; do
  dpkg -s "$pkg" &>/dev/null || to_install+=("$pkg")
done
[[ ${#to_install[@]} -gt 0 ]] && apt-get install -y "${to_install[@]}"

# MTA setup
if command -v msmtp &>/dev/null; then
  echo -e "${BLUE}[*] Configuring msmtp as the system MTA...${NC}"
  update-alternatives --install /usr/sbin/sendmail mta /usr/bin/msmtp 10
  update-alternatives --set mta /usr/bin/msmtp
  echo -e "${GREEN}[$CHECK] msmtp configured as default MTA${NC}"
  summary["MTA Setup"]="$CHECK"
else
  echo -e "${YELLOW}[!] msmtp not found, skipping MTA configuration${NC}"
fi

# UFW
if prompt_yes_no "[*] Enable UFW with SSH allowed and default rules?"; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw --force enable
  summary["Firewall"]="$CHECK"
fi

# Fail2Ban
if prompt_yes_no "[*] Enable Fail2Ban for SSH protection?"; then
  systemctl enable --now fail2ban
  summary["Fail2Ban"]="$CHECK"
fi

if [[ -f "$SCRIPT_DIR/fail2ban/jail.local" ]]; then
  echo -e "${BLUE}[*] Copying jail.local config...${NC}"
  cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
  systemctl restart fail2ban
fi

# RKHunter
if prompt_yes_no "[*] Initialize rkhunter properties DB now?"; then
  rkhunter --propupd -q || true
  summary["RKHunter DB Init"]="$CHECK"
fi

# ClamAV DB
CLAM_USER=$(getent passwd clamav | cut -d: -f1)
echo -e "${BLUE}[*] Updating ClamAV virus database...${NC}"
systemctl stop clamav-freshclam || true
sudo -u "$CLAM_USER" freshclam || true

if prompt_yes_no "[*] Enable clamd daemon and socket?"; then
  chown -R clamav:clamav /var/lib/clamav /var/log/clamav
  systemctl unmask clamav-daemon.socket
  systemctl unmask clamav-daemon.service
  systemctl enable --now clamav-daemon
  sleep 2
  if [[ -S /var/run/clamav/clamd.ctl ]]; then
    echo -e "${GREEN}[$CHECK] clamd is running and socket is available.${NC}"
    summary["Clamd"]="$CHECK"
  else
    echo -e "${RED}[!] clamd socket not found. Check service status.${NC}"
  fi
fi

# Lynis audit
if prompt_yes_no "[*] Run Lynis system audit now?"; then
  echo -e "${BLUE}[*] Running Lynis audit...${NC}"
  LYNIS_OUT="$HOME/secure-linux-server/logs/lynis-report.txt"
  mkdir -p "$(dirname "$LYNIS_OUT")"
  chmod 700 "$(dirname "$LYNIS_OUT")"
  lynis audit system --quiet > "$LYNIS_OUT" || true
  echo -e "${GREEN}[$CHECK] Lynis report saved to: $LYNIS_OUT${NC}"
  summary["Lynis Audit"]="$CHECK"
fi

# Disable root SSH
if prompt_yes_no "[*] Disable SSH root login (PermitRootLogin no)?"; then
  sed -i.bak -E 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
  systemctl restart ssh
  echo -e "${GREEN}[$CHECK] SSH root login disabled.${NC}"
  summary["SSH Root Login"]="$CHECK"
fi

# notify.sh
if prompt_yes_no "[*] Install notify.sh to default location?"; then
  NOTIFY_SRC="$SCRIPT_DIR/alerts/scripts/notify.sh"
  NOTIFY_DEST="$HOME/secure-linux-server/alerts/scripts/notify.sh"
  if [[ -f "$NOTIFY_DEST" ]]; then
    echo -e "${YELLOW}[!] notify.sh already exists, skipping copy.${NC}"
    summary["notify.sh"]="$CHECK"
  else
    mkdir -p "$(dirname "$NOTIFY_DEST")"
    chmod 700 "$(dirname "$NOTIFY_DEST")"
    cp "$NOTIFY_SRC" "$NOTIFY_DEST"
    chmod +x "$NOTIFY_DEST"
    echo -e "${GREEN}[+] notify.sh installed to $NOTIFY_DEST${NC}"
    summary["notify.sh"]="$CHECK"
  fi
fi

# Summary
SUMMARY_KEYS=(
  "System Upgrade"
  "Firewall"
  "Fail2Ban"
  "RKHunter DB Init"
  "Clamd"
  "MTA Setup"
  "Lynis Audit"
  "notify.sh"
  "Email Config"
  "SSH Root Login"
)

echo -e "\n${BLUE}========= Setup Summary =========${NC}"
for key in "${SUMMARY_KEYS[@]}"; do
  printf "%-20s %s\n" "$key:" "${summary[$key]}"

done
echo -e "${GREEN}\n[$CHECK] Setup complete.${NC}"
