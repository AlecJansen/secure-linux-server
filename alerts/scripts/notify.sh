#!/bin/bash

# notify.sh - Daily security scan and email notifier

set -euo pipefail
umask 077

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
LOGS=("${BASE_NAME}_rkhunter.log" "${BASE_NAME}_chkrootkit.log" "${BASE_NAME}_clamdscan.log")
STATUS_FILES=("${BASE_NAME}_rkhunter.status" "${BASE_NAME}_chkrootkit.status" "${BASE_NAME}_clamdscan.status")
REPORT="${BASE_NAME}_report.txt"

# Cleanup old logs
find "$LOG_DIR" -type f \( -name "*.log" -o -name "*.status" -o -name "*.txt" \) -mtime +14 -delete 2>/dev/null || true

# Check disk space
available_kb=$(df "$LOG_DIR" | awk 'NR==2 {print $4}')
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

  if timeout 900 nice -n 15 ionice -c 3 $cmd > "$log" 2>&1; then
    if [[ $tool == "rkhunter" ]]; then
      if grep -Eq '^(Warning:|Found|.*Trojan)' "$log"; then
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
    if [[ $tool == "rkhunter" ]] && grep -Eq '^(Warning:|Found|.*Trojan)' "$log"; then
      echo "WARN" > "$status"
      echo "[⚠️ ] $tool complete (with warnings)"
    else
      echo "FAIL" > "$status"
      echo "[❌] $tool failed"
    fi
  fi
}

# Launch scans in parallel
run_scan "rkhunter" "sudo rkhunter --check --rwo --nocolors" "${LOGS[0]}" "${STATUS_FILES[0]}" &
PIDS+=("$!")
run_scan "chkrootkit" "sudo chkrootkit" "${LOGS[1]}" "${STATUS_FILES[1]}" &
PIDS+=("$!")
run_scan "clamdscan" "clamdscan --fdpass $HOME" "${LOGS[2]}" "${STATUS_FILES[2]}" &
PIDS+=("$!")

wait

# Read scan results
statuses=($(cat "${STATUS_FILES[@]}"))
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
  found_lines=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^(Warning:|Found|.*Trojan) ]]; then
      echo "• $line"
      found_lines=true
    elif [[ "$found_lines" = true && "$line" =~ ^[[:space:]] ]]; then
      echo "$line"
    fi
  done < "${LOGS[0]}"
  $found_lines || echo "No findings reported"
  echo ""

  echo "📄 CHKROOTKIT Warnings:"
  found_lines=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^WARNING: ]]; then
      echo "• $line"
      found_lines=true
    elif [[ "$found_lines" = true && "$line" =~ ^[[:space:]] ]]; then
      echo "$line"
    fi
  done < "${LOGS[1]}"
  $found_lines || echo "No warnings reported"
  echo ""

  echo "📄 CLAMDSCAN Issues:"
  if grep -q 'Infected files: [^0]' "${LOGS[2]}"; then
    awk '/Infected files:/,EOF' "${LOGS[2]}"
  else
    awk '/Infected files:/ { print "• " $0 } /WARNING:/ { print "• " $0 }' "${LOGS[2]}" |
      grep -vE '(snap|docker|urandom|random|zero|netdata|not supported)' || echo "No notable warnings found"
  fi
  echo ""
} > "$REPORT"

# Email report
mail -s "[Security Scan] $HOSTNAME - $DATE_TIME" "$EMAIL" < "$REPORT" && \
  echo "[📬] Email sent" || echo "[❌] Email failed"

# Cleanup
rm -f "${STATUS_FILES[@]}" 2>/dev/null || true

# Exit code
[[ "${statuses[*]}" =~ "FAIL" ]] && { echo "[⚠️ ] Scan(s) failed"; exit 1; }
echo "[🏁] All scans completed successfully"
