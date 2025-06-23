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

# Configuration
EMAIL="alecjansen1@gmail.com"
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

printf "\n🔐 ========= Daily Security Scans ========= 🔐\n\n"
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
  awk '/^Warning:|^Found|.*[Tt]rojan/,/^$/' "${LOGS[0]}" | sed '/^$/q'
  echo ""

  echo "📄 CHKROOTKIT Warnings:"
  awk '/^WARNING:|\/usr\/|\/sbin\/|\/lib\// { print "• " $0 }' "${LOGS[1]}" || echo "No warnings reported"
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
} | msmtp --file="$HOME/.msmtprc" --account=gmail "$EMAIL"
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
