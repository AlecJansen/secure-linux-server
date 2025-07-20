#!/bin/bash
set -euo pipefail

# Color setup (disable if --no-color)
if [[ "${1:-}" == "--no-color" ]] || ! [[ -t 1 ]]; then
  GREEN=""; RED=""; YELLOW=""; CYAN=""; NC=""; BOLD=""
else
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color
  BOLD='\033[1m'
fi

SUMMARY_PRINTED=0

print_summary() {
  # Prevent duplicate printing
  [[ $SUMMARY_PRINTED -eq 1 ]] && return
  SUMMARY_PRINTED=1
  {
    echo -e "\n${BOLD}$( [[ $SYSTEM_STATUS == *OK* ]] && echo -e \"${GREEN}✓\" || echo -e \"${RED}✗\" ) Full update completed. (UTC: $(date -u))${NC}\n"
    echo -e "${YELLOW}------ TOOL STATUS SUMMARY ------${NC}"
    echo -e "  $SYSTEM_STATUS"
    for status in "${TOOL_STATUS[@]}"; do
      if [[ $status == *OK* ]]; then
        echo -e "  ${GREEN}$status${NC}"
      elif [[ $status == *Not\ installed* ]]; then
        echo -e "  ${YELLOW}$status${NC}"
      else
        echo -e "  ${RED}$status${NC}"
      fi
    done
    echo -e "${YELLOW}---------------------------------${NC}"
  } | tee -a "$LOG_FILE"
  echo -e "\n${GREEN}${BOLD}🚀 All done!${NC} View full logs at $LOG_FILE"
}
trap print_summary EXIT

# Banner
echo -e "${GREEN}${BOLD}"
cat <<'BANNER'
   _____ _       _____       _    _ _____  _____       _______ ______ 
  / ____| |     / ____|     | |  | |  __ \|  __ \   /\|__   __|  ____|
 | (___ | |    | (___ ______| |  | | |__) | |  | | /  \  | |  | |__   
  \___ \| |     \___ \______| |  | |  ___/| |  | |/ /\ \ | |  |  __|  
  ____) | |____ ____) |     | |__| | |    | |__| / ____ \| |  | |____ 
 |_____/|______|_____/       \____/|_|    |_____/_/    \_\_|  |______|
                                                                      
                 Secure-Linux-Server Update              
BANNER
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[-] This script must be run as root. Try: sudo $0${NC}"
    exit 1
fi

if pgrep -x "apt" >/dev/null || pgrep -x "dpkg" >/dev/null; then
    echo -e "${YELLOW}[-] APT or dpkg is currently running. Please wait for it to finish.${NC}"
    exit 1
fi

LOG_DIR="/var/log/secure-linux-server"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update-$(date -u '+%Y-%m-%d_%H-%M-%S_UTC').log"
ls -1t "$LOG_DIR"/update-*.log 2>/dev/null | tail -n +11 | xargs -r rm -- || true

echo -e "${CYAN}[*] Starting full system update (UTC: $(date -u))...${NC}" | tee "$LOG_FILE"

SYSTEM_STATUS="system: ✅ OK"
TOOL_STATUS=()

echo -e "${YELLOW}[+] Updating system packages...${NC}" | tee -a "$LOG_FILE"
if \
   DEBIAN_FRONTEND=noninteractive apt-get update | tee -a "$LOG_FILE" && \
   DEBIAN_FRONTEND=noninteractive apt-get upgrade -y | tee -a "$LOG_FILE" && \
   DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y | tee -a "$LOG_FILE" && \
   DEBIAN_FRONTEND=noninteractive apt-get autoremove -y | tee -a "$LOG_FILE" && \
   DEBIAN_FRONTEND=noninteractive apt-get autoclean -y | tee -a "$LOG_FILE"
then
    SYSTEM_STATUS="system: ✅ OK"
else
    SYSTEM_STATUS="system: ❌ ERROR (Check log)"
fi

echo -e "${YELLOW}[+] Upgrading Lynis...${NC}" | tee -a "$LOG_FILE"
DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y lynis | tee -a "$LOG_FILE"

for tool in rkhunter lynis chkrootkit freshclam suricata-update; do
    if command -v "$tool" &>/dev/null; then
        case "$tool" in
            rkhunter)
                echo -e "\n${YELLOW}[+] Updating rkhunter...${NC}" | tee -a "$LOG_FILE"
                if rkhunter --update | tee -a "$LOG_FILE" && rkhunter --propupd -q | tee -a "$LOG_FILE"; then
                    TOOL_STATUS+=("rkhunter: ✅ OK")
                else
                    TOOL_STATUS+=("rkhunter: ❌ ERROR (Check log)")
                fi
                ;;
            lynis)
                echo -e "\n${YELLOW}[+] Updating lynis...${NC}" | tee -a "$LOG_FILE"
                if lynis update info | tee -a "$LOG_FILE"; then
                    TOOL_STATUS+=("lynis: ✅ OK")
                else
                    TOOL_STATUS+=("lynis: ❌ ERROR (Check log)")
                fi
                ;;
            chkrootkit)
                echo -e "\n${YELLOW}[+] Running chkrootkit scan...${NC}" | tee -a "$LOG_FILE"
                if chkrootkit | tee -a "$LOG_FILE"; then
                    TOOL_STATUS+=("chkrootkit: ✅ OK")
                else
                    TOOL_STATUS+=("chkrootkit: ❌ ERROR (Check log)")
                fi
                ;;
            freshclam)
                echo -e "\n${YELLOW}[+] Updating ClamAV database...${NC}" | tee -a "$LOG_FILE"
                if freshclam | tee -a "$LOG_FILE"; then
                    TOOL_STATUS+=("clamav: ✅ OK")
                else
                    TOOL_STATUS+=("clamav: ❌ ERROR (Check log)")
                fi
                if systemctl is-active --quiet clamav-daemon; then
                    echo -e "${YELLOW}[+] Restarting ClamAV daemon...${NC}" | tee -a "$LOG_FILE"
                    systemctl restart clamav-daemon | tee -a "$LOG_FILE"
                fi
                ;;
            suricata-update)
                echo -e "\n${YELLOW}[+] Ensuring Suricata rule sources are up to date...${NC}" | tee -a "$LOG_FILE"
                if suricata-update update-sources | tee -a "$LOG_FILE"; then
                    echo -e "${GREEN}[+] Suricata sources updated.${NC}" | tee -a "$LOG_FILE"
                else
                    echo -e "${RED}[WARNING] Failed to update Suricata sources!${NC}" | tee -a "$LOG_FILE"
                    TOOL_STATUS+=("suricata: ❌ ERROR (update-sources failed)")
                fi
                echo -e "${YELLOW}[+] Updating Suricata rules...${NC}" | tee -a "$LOG_FILE"
                if suricata-update | tee -a "$LOG_FILE"; then
                    TOOL_STATUS+=("suricata: ✅ OK")
                else
                    TOOL_STATUS+=("suricata: ❌ ERROR (Check log)")
                fi
                if systemctl is-active --quiet suricata; then
                    echo -e "${YELLOW}[+] Restarting Suricata service...${NC}" | tee -a "$LOG_FILE"
                    systemctl restart suricata | tee -a "$LOG_FILE"
                fi
                ;;
        esac
    else
        TOOL_STATUS+=("$tool: ⚠️ Not installed")
    fi
done

if command -v ufw &>/dev/null; then
    echo -e "\n${CYAN}[+] Checking UFW firewall status...${NC}" | tee -a "$LOG_FILE"
    (ufw status verbose | tee -a "$LOG_FILE" || echo -e "${YELLOW}[Warn] UFW status check failed.${NC}" | tee -a "$LOG_FILE")
    (ufw reload | tee -a "$LOG_FILE" || echo -e "${YELLOW}[Warn] UFW reload failed.${NC}" | tee -a "$LOG_FILE")
fi

if command -v fail2ban-client &>/dev/null; then
    echo -e "\n${CYAN}[+] Reloading Fail2Ban and checking jail status...${NC}" | tee -a "$LOG_FILE"
    if systemctl is-active --quiet fail2ban; then
        (systemctl reload fail2ban | tee -a "$LOG_FILE" || echo -e "${YELLOW}[Warn] Fail2Ban reload failed.${NC}" | tee -a "$LOG_FILE")
        (fail2ban-client status | tee -a "$LOG_FILE" || echo -e "${YELLOW}[Warn] Fail2Ban status failed.${NC}" | tee -a "$LOG_FILE")
    else
        echo -e "${YELLOW}[Warn] Fail2Ban not running, skipping reload/status.${NC}" | tee -a "$LOG_FILE"
    fi
fi

# The summary will be printed at script exit due to trap

