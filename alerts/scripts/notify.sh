#!/bin/bash

# notify.sh - Daily security scan and email notifier

set -euo pipefail
umask 077

PIDS=()
trap 'echo -e "\n🚨 Script interrupted. Killing scans..."; for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done; exit 1' INT TERM

# Check for msmtp
if ! command -v msmtp &> /dev/null; then
  echo "❌ Error: 'msmtp' command not found. Please install it."
  exit 1
fi

# Detect and use the original user's msmtp config even when running with sudo
if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  USER_HOME="$HOME"
fi
MSMTP_CONFIG="$USER_HOME/.msmtprc"

if [[ ! -f "$MSMTP_CONFIG" ]]; then
  echo "❌ Error: msmtp config not found at $MSMTP_CONFIG"
  echo "   Please create it with your SMTP credentials."
  echo "   See: https://github.com/secure-linux-server/secure-linux-server/wiki/Email-Alerts"
  exit 1
fi

# Configuration
EMAIL="alecjansen1@gmail.com"

# Configuration
HOSTNAME="voyd"
LOG_DIR="$HOME/secure-linux-server/logs"
DATE_TIME=$(date +%F_%H-%M-%S)
REQUIRED_SPACE_MB=500

# Setup
mkdir -p "$LOG_DIR"
BASE_NAME="$LOG_DIR/${DATE_TIME}"
LOGS=("${BASE_NAME}_rkhunter.log" "${BASE_NAME}_chkrootkit.log" "${BASE_NAME}_clamdscan.log")
STATUS_FILES=("${BASE_NAME}_rkhunter.status" "${BASE_NAME}_chkrootkit.status" "${BASE_NAME}_clamdscan.status")
REPORT="${BASE_NAME}_report.txt"

# Cleanup old logs
find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.status" -o -name "*.txt" \) -mtime +14 -delete 2>/dev/null || true

# Check disk space
if ! available_kb=$(df "$LOG_DIR" 2>/dev/null | awk 'NR==2 {print $4}'); then
  echo "❌ Error: Unable to check disk space for $LOG_DIR"
  exit 1
fi
available_mb=$(( available_kb / 1024 ))
available_gb=$(( available_mb / 1024 ))

if [[ $available_mb -lt $REQUIRED_SPACE_MB ]]; then
  echo "❌ Error: Need ${REQUIRED_SPACE_MB}MB, have ${available_mb}MB"
  exit 1
fi

printf "\n🔐 ========= Daily Security Scan ========= 🔐\n\n"
echo "[💾] Disk space OK: ${available_gb}GB available"
echo "[•] Starting scans..."

# Initialize status files
for file in "${STATUS_FILES[@]}"; do echo "FAIL" > "$file"; done

# Scan runner
run_scan() {
  local tool=$1 cmd=$2 log=$3 status=$4

  ( # Run inside subshell so PID can be tracked
    if timeout 900 nice -n 15 ionice -c 3 $cmd > "$log" 2>&1; then
      if [[ $tool == "rkhunter" ]]; then
        if grep -Eq '^Warning:|^Found|.*[Tt]rojan' "$log"; then
          echo "WARN" > "$status"
          echo "[⚠️ ] $tool complete (with warnings)"
        else
          echo "OK" > "$status"
          echo "[✅] $tool complete"
        fi
      elif [[ $tool == "clamdscan" ]]; then
        infected=$(grep -oP 'Infected files:\s+\K\d+' "$log" || echo "0")
        if [[ "$infected" -gt 0 ]]; then
          echo "WARN" > "$status"
          echo "[⚠️ ] $tool complete (infected files found)"
        else
          echo "OK" > "$status"
          echo "[✅] $tool complete"
        fi
      else
        echo "OK" > "$status"
        echo "[✅] $tool complete"
      fi
    else
      if [[ $tool == "clamdscan" ]]; then
        infected=$(grep -oP 'Infected files:\s+\K\d+' "$log" || echo "0")
        if [[ "$infected" -eq 0 ]]; then
          echo "OK" > "$status"
          echo "[✅] $tool complete (non-fatal warnings)"
          exit 0
        fi
      fi
      if [[ $tool == "rkhunter" ]] && grep -Eq '^Warning:|^Found|.*[Tt]rojan' "$log"; then
        echo "WARN" > "$status"
        echo "[⚠️ ] $tool complete (with warnings)"
      else
        echo "FAIL" > "$status"
        echo "[❌] $tool failed"
      fi
    fi
  ) &
  PIDS+=("$!")
}

# Launch scans
run_scan "rkhunter" "sudo rkhunter --check --rwo --nocolors" "${LOGS[0]}" "${STATUS_FILES[0]}"
run_scan "chkrootkit" "sudo chkrootkit" "${LOGS[1]}" "${STATUS_FILES[1]}"
run_scan "clamdscan" "sudo clamdscan --fdpass $HOME" "${LOGS[2]}" "${STATUS_FILES[2]}"

wait || true  # Don't fail if a background job was killed

# Read scan results (wait a moment for file writes to complete)
sleep 1
statuses=()
for status_file in "${STATUS_FILES[@]}"; do
  if [[ -f "$status_file" ]]; then
    statuses+=($(cat "$status_file"))
  else
    statuses+=("FAIL")
  fi

done
echo ""

# Format summary
summary_block="🧾 Summary:\n   🛡 RKHUNTER   → ${statuses[0]}\n   🐛 CHKROOTKIT → ${statuses[1]}\n   🧬 CLAMDSCAN  → ${statuses[2]}"

{
  echo "🔒 Daily Security Scan Report for $HOSTNAME - $DATE_TIME"
  echo "============================================================"
  echo ""
  echo -e "$summary_block"
  echo ""

  echo "📄 RKHUNTER Findings:"
  RKHUNTER_OUTPUT=$(awk '/^Warning:|^Found|.*[Tt]rojan/,/^$/' "${LOGS[0]}" | sed '/^$/q')
  if [[ -z "$RKHUNTER_OUTPUT" ]]; then
    echo "No warnings reported"
  else
    echo "$RKHUNTER_OUTPUT"
  fi
  echo ""

  echo "📄 CHKROOTKIT Warnings:"
  CHKROOTKIT_WARNINGS=$(awk '/^WARNING:|\/usr\/|\/sbin\/|\/lib\// { print "• " $0 }' "${LOGS[1]}" | \
    grep -vE "PACKET SNIFFER|twisted|fail2ban|\.htaccess|\.gitignore|\.document|\.build-id|No such file or directory")
  if [[ -z "$CHKROOTKIT_WARNINGS" ]]; then
    echo "No warnings reported"
  else
    echo "$CHKROOTKIT_WARNINGS"
  fi
  echo ""

  echo "📄 CLAMDSCAN Issues:"
  if grep -qE 'Infected files: [1-9][0-9]*' "${LOGS[2]}"; then
    awk '/Infected files:/{p=1} p' "${LOGS[2]}"
  else
    awk '/Infected files:/ { print "• " $0 } /WARNING:/ { print "• " $0 }' "${LOGS[2]}" |
      grep -vE '(snap|docker|urandom|random|zero|netdata|not supported)' || echo "No notable warnings found"
  fi
  echo ""
} > "$REPORT"

# Email report
SUBJECT="Security Report: ${HOSTNAME^^} - ${DATE_TIME}"
echo "[📤] Sending email report to $EMAIL..."
{
  echo "Subject: $SUBJECT"
  echo "From: $EMAIL"
  echo "To: $EMAIL"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo ""
  cat "$REPORT"
} | msmtp --file="$MSMTP_CONFIG" --account=gmail "$EMAIL"
status=$?
if [[ $status -eq 0 ]]; then
  echo "[📬] Email sent"
else
  echo "[❌] Email failed"
fi

# Cleanup
rm -f "${STATUS_FILES[@]}" 2>/dev/null || true

# Exit code
[[ "${statuses[*]}" =~ "FAIL" ]] && { echo "[⚠️ ] Scan(s) failed"; exit 1; }
echo "[🏁] All scans completed successfully"

# Offer to set up a Cron job for notify.sh if running interactively
if [[ -t 1 && -t 0 ]]; then
  echo -e "\n🛠️  Would you like to schedule automatic daily/weekly/monthly scans via cron?"
  echo "   1) Daily at 8am (default)"
  echo "   2) Weekly (Sunday 8am)"
  echo "   3) Monthly (1st day 8am)"
  read -rp "Select [1/2/3] or press Enter for daily: " schedule_choice

  case "$schedule_choice" in
    2)
      cron_expr="0 8 * * 0"
      human_sched="weekly (Sundays at 8am)"
      ;;
    3)
      cron_expr="0 8 1 * *"
      human_sched="monthly (1st at 8am)"
      ;;
    *)
      cron_expr="0 8 * * *"
      human_sched="daily (8am)"
      ;;
  esac

  script_path="$(realpath "$0")"
  (crontab -l 2>/dev/null; echo "$cron_expr bash \"$script_path\"") | sort | uniq | crontab -

  echo -e "\n✅ Cron job set: $human_sched"
  echo "   (To remove, run: crontab -e)"
fi
