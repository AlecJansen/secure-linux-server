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
echo "  \\___ \\ / _ \\ '__\\ \\ / / |/ __/ _ \\ / _ \\ / __/ __/ _ \\\" 
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

TOOLS=(ufw fail2ban lynis rkhunter clamav chkrootkit unattended-upgrades mailutils msmtp suricata jq)
INSTALL_LIST=()

for tool in "${TOOLS[@]}"; do
  read -p "[*] Install $tool? (y/n): " choice
  if [[ "$choice" =~ ^[Yy]$ ]]; then
    INSTALL_LIST+=("$tool")
  fi
done

if [[ ${#INSTALL_LIST[@]} -gt 0 ]]; then
  echo -e "${BLUE}[*] Installing selected tools: ${INSTALL_LIST[*]}${NC}"
  apt install -y "${INSTALL_LIST[@]}"
fi

contains_tool() {
  printf '%s\n' "${INSTALL_LIST[@]}" | grep -qx "$1"
}

# Remaining configuration steps follow unchanged...
# [UFW, Fail2Ban, RKHunter, ClamAV setup logic continues here]

if contains_tool "suricata"; then
  echo -e "${BLUE}[*] Configuring Suricata...${NC}"
  mkdir -p /var/log/suricata
  chown suricata:suricata /var/log/suricata

  DETECTED_IFACE=$(ip -brief address show | awk '/UP/ && !/lo/ {print $1; exit}')
  echo -e "Detected network interface: ${YELLOW}$DETECTED_IFACE${NC}"
  read -p "[*] Use this interface for Suricata? (y/n): " use_iface
  if [[ "$use_iface" =~ ^[Yy]$ ]]; then
    INTERFACE="$DETECTED_IFACE"
  else
    read -p "Enter the desired network interface name: " INTERFACE
  fi

  cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.bak

  echo -e "${BLUE}[*] Patching Suricata interface config...${NC}"
  awk -v iface="$INTERFACE" '
    BEGIN {in_afpacket=0}
    /^af-packet:/ {print; in_afpacket=1; next}
    in_afpacket == 1 && /^\s*- interface:/ { next }
    in_afpacket == 1 && /^\S/ {
      in_afpacket=0
      print "  - interface: " iface
      print "    threads: auto"
      print "    promisc: true"
      print "    cluster-id: 99"
      print "    cluster-type: cluster_flow"
      print "    defrag: yes"
    }
    { if (in_afpacket != 1) print }
  ' /etc/suricata/suricata.yaml.bak > /etc/suricata/suricata.yaml

  if ! grep -q "$INTERFACE" /etc/suricata/suricata.yaml; then
    echo -e "${RED}[!] Warning: Suricata interface not patched correctly. Check configuration.${NC}"
  fi

  echo -e "${BLUE}[*] Validating Suricata config...${NC}"
  if suricata -T -c /etc/suricata/suricata.yaml -v; then
    echo -e "${GREEN}[✓] Config valid. Restarting Suricata...${NC}"
    systemctl stop suricata
    sleep 1
    systemctl start suricata && echo -e "${GREEN}[+] Suricata started successfully.${NC}" || echo -e "${RED}[!] Failed to start Suricata. Check system logs.${NC}"
  else
    echo -e "${RED}[!] Suricata config invalid. Check /etc/suricata/suricata.yaml.${NC}"
  fi
fi
