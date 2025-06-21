#!/bin/bash

# notify.sh - Daily security scan and email notifier

set -euo pipefail
umask 077

# Track background PIDs
PIDS=()

trap 'echo -e "\n🚨 Script interrupted. Killing scans..."; for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done; exit 1' INT TERM

# Check for mail command
if ! command -v mail &> /dev/null; then
  echo "❌ Error: 'mail' command not found. Please install 'mailutils' or similar."
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
LOGS=("${BASE_NAME}_rkhunter.log" "${BASE_NAME}_lynis.log" "${BASE_NAME}_chkrootkit.log")
STATUS_FILES=("${BASE_NAME}_rkhunter.status" "${BASE_NAME}_lynis.status" "${BASE_NAME}_chkrootkit.status")
REPORT="${BASE_NAME}_report.txt"

# Cleanup and setup
find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.status" -o -name "*.txt" \) -mtime +14 -delete 2>/dev/null || true

# Check disk space
available_mb=$(( $(df "$LOG_DIR" | awk 'NR==2 {print $4}') / 1024 ))
if [[ $available_mb -lt $REQUIRED_SPACE_MB ]]; then
  echo "❌ Error: Need ${REQUIRED_SPACE_MB}MB, have ${available_mb}MB"
  exit 1
fi

printf "\n🔐 ========= Daily Security Scans ========= 🔐\n\n"
echo "[💾] Disk space OK: ${available_mb}MB available"
echo "[•] Starting scans..."

# Initialize status files
for file in "${STATUS_FILES[@]}"; do echo "FAIL" > "$file"; done

# Run scans in parallel
run_scan() {
  local tool=$1 cmd=$2 log=$3 status=$4
  if timeout 900 nice -n 15 ionice -c 3 $cmd > "$log" 2>&1; then
    echo "OK" > "$status"
    echo "[✅] $tool complete"
  elif [[ $tool == "rkhunter" ]] && grep -q '^Warning:' "$log"; then
    echo "WARN" > "$status"  
    echo "[⚠️] $tool warnings"
  else
    echo "FAIL" > "$status"
    echo "[❌] $tool failed"
  fi
}

run_scan "rkhunter" "sudo rkhunter --check --rwo --nocolors" "${LOGS[0]}" "${STATUS_FILES[0]}" &
PIDS+=("$!")
run_scan "lynis" "sudo lynis audit system --cronjob" "${LOGS[1]}" "${STATUS_FILES[1]}" &  
PIDS+=("$!")
run_scan "chkrootkit" "sudo chkrootkit" "${LOGS[2]}" "${STATUS_FILES[2]}" &
PIDS+=("$!")

wait

# Read results and create report
statuses=($(cat "${STATUS_FILES[@]}"))
echo ""

{
  echo "🔒 Daily Security Scan Report for $HOSTNAME - $DATE_TIME"
  echo "========================================================"
  printf "%-18s %s\n" "🛡 RKHUNTER:" "${statuses[0]}"
  printf "%-18s %s\n" "🔍 LYNIS:" "${statuses[1]}"  
  printf "%-18s %s\n" "🐛 CHKROOTKIT:" "${statuses[2]}"
  echo ""
  
  for i in {0..2}; do
    tool_names=("RKHUNTER" "LYNIS" "CHKROOTKIT")
    echo "📄 -- ${tool_names[i]} OUTPUT (last 20 lines) --"
    [[ -s "${LOGS[i]}" ]] && tail -n 20 "${LOGS[i]}" || echo "No output available"
    echo ""
  done
  
  # Chkrootkit warnings
  echo "📄 -- CHKROOTKIT WARNINGS --"
  if grep -q '^WARNING:' "${LOGS[2]}" 2>/dev/null; then
    awk '/^WARNING:/,/^$/' "${LOGS[2]}" | head -n 50
  else
    echo "No specific warnings found"
  fi
} > "$REPORT"

# Send email and cleanup
mail -s "[Security Scan] $HOSTNAME - $DATE_TIME" "$EMAIL" < "$REPORT" && \
  echo "[📬] Email sent" || echo "[❌] Email failed"

rm -f "${STATUS_FILES[@]}" 2>/dev/null || true

# Exit with error if any scan failed
[[ "${statuses[*]}" =~ "FAIL" ]] && { echo "[⚠️] Scan(s) failed"; exit 1; }
echo "[🏁] All scans completed successfully"
