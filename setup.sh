#!/bin/bash

# setup.sh - Interactive Secure Linux Server Setup (improved version)

set -euo pipefail

# --- Color and symbol setup ---
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
NC="\033[0m"
CHECK="✓"
CROSS="✗"

# --- Step tracking for error reporting ---
CURRENT_STEP="Initialization"
error_exit() {
  echo -e "${RED}[!] Error during: $CURRENT_STEP. Exiting.${NC}"
  exit 1
}
trap error_exit ERR

# --- Root privilege check ---
if [[ $EUID -ne 0 ]]; then
  echo -e "${YELLOW}[!] Script not running as root. Attempting to re-execute with sudo...${NC}"
  exec sudo "$0" "$@"
fi

# --- Logging setup ---
LOG_FILE="$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)/secure-linux-server/setup-$(date +%F).log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Step: Welcome Header ---
echo -e "${BLUE}"
echo "  ____                  _             _            "
echo " / ___|  ___ _ ____   _(_) ___ ___   / \\   ___ ___ "
echo " \\___ \\ / _ \\ '__\\ \\ / / |/ __/ _ \\ / _ \\ / __/ _ \\"
echo "  ___) |  __/ |   \\ V /| | (_|  __// ___ \\ (_|  __/"
echo " |____/ \\___|_|    \\_/ |_|\\___\\___/_/   \\_\\___\\___/"
echo -e "${NC}"
echo -e "${YELLOW}Welcome to the Secure Linux Server Setup Script!${NC}\n"

# --- Step: Connectivity check ---
CURRENT_STEP="Internet Connectivity Check"
if ! ping -c1 1.1.1.1 >/dev/null 2>&1; then
  echo -e "${RED}[!] No internet connection detected. Aborting.${NC}"
  exit 1
fi

# --- Step: Ensure apt-get available ---
CURRENT_STEP="apt-get Presence Check"
if ! command -v apt-get &> /dev/null; then
  echo -e "${RED}[!] apt-get is missing. This script requires a Debian-based system.${NC}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Summary ---
declare -gA summary
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
    ["Unattended Upgrades"]="Skipped"
    ["Broken Packages"]="No"
    ["Held Packages"]="No"
  )
}
init_summary

# --- Step: System Upgrade ---
CURRENT_STEP="System Upgrade"
prompt_yes_no() {
  local prompt="$1"
  local choice
  read -rp "$prompt (Y/n): " choice
  [[ -z "$choice" || "$choice" =~ ^[Yy]$ ]]
}

if prompt_yes_no "[*] Proceed with system update and upgrade?"; then
  apt-get update && apt-get upgrade -y
  summary["System Upgrade"]="$CHECK"
else
  summary["System Upgrade"]="$CROSS Skipped"
fi

# --- Step: Check for held/broken packages ---
CURRENT_STEP="Checking for Broken/Held Packages"
broken_pkgs=$(dpkg --audit || true)
if [[ -n "$broken_pkgs" && "$broken_pkgs" != " " ]]; then
  echo -e "${YELLOW}[!] Broken packages found:\n$broken_pkgs${NC}"
  summary["Broken Packages"]="${CROSS} Broken Packages"
fi

held_pkgs=$(apt-mark showhold || true)
if [[ -n "$held_pkgs" && "$held_pkgs" != " " ]]; then
  echo -e "${YELLOW}[!] Held packages:\n$held_pkgs${NC}"
  summary["Held Packages"]="${CROSS} Held Packages"
fi

# --- Step: Email Config ---
CURRENT_STEP="Alert Email Configuration"
validate_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

USER_HOME="$(getent passwd ${SUDO_USER:-$USER} | cut -d: -f6)"
CONFIG_DIR="$USER_HOME/secure-linux-server/config"
CONFIG_FILE="$CONFIG_DIR/alert.conf"
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

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
  # Backup config if exists
  if [[ -f "$CONFIG_FILE" ]]; then
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak-$(date +%s)"
  fi
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

# --- Step: Install tools ---
CURRENT_STEP="Installing Packages"
tools=(ufw fail2ban lynis rkhunter clamav clamav-daemon chkrootkit unattended-upgrades mailutils msmtp)
echo -e "${BLUE}[*] Installing required packages...${NC}"
to_install=()
for pkg in "${tools[@]}"; do
  dpkg -s "$pkg" &>/dev/null || to_install+=("$pkg")
done
[[ ${#to_install[@]} -gt 0 ]] && apt-get install -y "${to_install[@]}"
apt-get autoremove -y && apt-get clean

# --- Step: Unattended Upgrades ---
CURRENT_STEP="Configuring Unattended Upgrades"
if [[ -f /etc/apt/apt.conf.d/50unattended-upgrades ]]; then
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl enable --now unattended-upgrades
  summary["Unattended Upgrades"]="$CHECK"
else
  summary["Unattended Upgrades"]="${CROSS} Not found"
fi

# --- Step: MTA setup ---
CURRENT_STEP="Configuring msmtp MTA"
if command -v msmtp &>/dev/null; then
  update-alternatives --install /usr/sbin/sendmail mta /usr/bin/msmtp 10
  update-alternatives --set mta /usr/bin/msmtp
  echo -e "${GREEN}[$CHECK] msmtp configured as default MTA${NC}"
  summary["MTA Setup"]="$CHECK"
else
  echo -e "${YELLOW}[!] msmtp not found, skipping MTA configuration${NC}"
  summary["MTA Setup"]="${CROSS} Not found"
fi

# --- Step: UFW ---
CURRENT_STEP="UFW Firewall Setup"
if prompt_yes_no "[*] Enable UFW with SSH allowed and default rules?"; then
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh
  ufw --force enable
  summary["Firewall"]="$CHECK"
else
  summary["Firewall"]="$CROSS Skipped"
fi

# --- Step: Fail2Ban ---
CURRENT_STEP="Fail2Ban Setup"
if prompt_yes_no "[*] Enable Fail2Ban for SSH protection?"; then
  systemctl enable --now fail2ban
  summary["Fail2Ban"]="$CHECK"
else
  summary["Fail2Ban"]="$CROSS Skipped"
fi

if [[ -f "$SCRIPT_DIR/fail2ban/jail.local" ]]; then
  echo -e "${BLUE}[*] Copying jail.local config...${NC}"
  cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
  systemctl restart fail2ban
fi

# --- Step: RKHunter ---
CURRENT_STEP="RKHunter DB Init"
if prompt_yes_no "[*] Initialize rkhunter properties DB now?"; then
  rkhunter --propupd -q || true
  summary["RKHunter DB Init"]="$CHECK"
else
  summary["RKHunter DB Init"]="$CROSS Skipped"
fi

# --- Step: ClamAV DB ---
CURRENT_STEP="ClamAV Update"
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
    summary["Clamd"]="${CROSS} Not running"
  fi
else
  summary["Clamd"]="$CROSS Not Enabled"
fi

# --- Step: Lynis audit ---
CURRENT_STEP="Lynis System Audit"
if prompt_yes_no "[*] Run Lynis system audit now?"; then
  echo -e "${BLUE}[*] Running Lynis audit...${NC}"
  LYNIS_OUT="$USER_HOME/secure-linux-server/logs/lynis-report.txt"
  mkdir -p "$(dirname "$LYNIS_OUT")"
  chmod 700 "$(dirname "$LYNIS_OUT")"
  lynis audit system --quiet > "$LYNIS_OUT" || true
  echo -e "${GREEN}[$CHECK] Lynis report saved to: $LYNIS_OUT${NC}"
  summary["Lynis Audit"]="$CHECK"
else
  summary["Lynis Audit"]="$CROSS Skipped"
fi

# --- Step: Disable root SSH ---
CURRENT_STEP="Disabling SSH Root Login"
if prompt_yes_no "[*] Disable SSH root login (PermitRootLogin no)?"; then
  SSHD_CONFIG="/etc/ssh/sshd_config"
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak-$(date +%s)"
  sed -i -E 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' "$SSHD_CONFIG"
  systemctl restart ssh
  echo -e "${GREEN}[$CHECK] SSH root login disabled.${NC}"
  summary["SSH Root Login"]="$CHECK"
else
  summary["SSH Root Login"]="$CROSS Not Modified"
fi

# --- Step: Install notify.sh ---
CURRENT_STEP="notify.sh Install"
if prompt_yes_no "[*] Install notify.sh to default location?"; then
  NOTIFY_SRC="$SCRIPT_DIR/alerts/scripts/notify.sh"
  NOTIFY_DEST="$USER_HOME/secure-linux-server/alerts/scripts/notify.sh"
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
else
  summary["notify.sh"]="$CROSS Not Installed"
fi

# --- Final summary ---
SUMMARY_KEYS=(
  "System Upgrade"
  "Broken Packages"
  "Held Packages"
  "Firewall"
  "Fail2Ban"
  "RKHunter DB Init"
  "Clamd"
  "MTA Setup"
  "Lynis Audit"
  "notify.sh"
  "Email Config"
  "SSH Root Login"
  "Unattended Upgrades"
)

echo -e "\n${BLUE}========= Setup Summary =========${NC}"
for key in "${SUMMARY_KEYS[@]}"; do
  printf "%-22s %s\n" "$key:" "${summary[$key]}"
done

SUMMARY_PATH="$USER_HOME/secure-linux-server/setup-summary-$(date +%F_%H-%M-%S).txt"
for key in "${SUMMARY_KEYS[@]}"; do
  printf "%-22s %s\n" "$key:" "${summary[$key]}"
done > "$SUMMARY_PATH"
echo -e "${GREEN}\n[$CHECK] Setup complete. Summary saved to $SUMMARY_PATH.${NC}"

if [[ "${summary["Broken Packages"]}" != "No" || "${summary["Held Packages"]}" != "No" ]]; then
  echo -e "${YELLOW}\n[!] Please resolve broken or held packages before continuing.${NC}"
fi

echo -e "${BLUE}\n[!] Review all summary lines marked with $CROSS for manual follow-up if needed.${NC}"

