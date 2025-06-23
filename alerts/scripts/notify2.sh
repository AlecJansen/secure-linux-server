#!/bin/bash

# notify2.sh - Advanced daily security scan and email notifier

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
available_kb=$(df "$LOG_DIR" | awk 'NR==2 {print $4}')
available_mb=$((available_kb / 1024))
available_gb=$(awk "BEGIN {printf \"%.1f\", $available_mb/1024}")

if [[ $available_mb -lt $REQUIRED_SPACE_MB ]]; then
  echo "❌ Error: Need ${REQUIRED_SPACE_MB}MB, have ${available_gb}GB"
  exit 1
fi

printf "\n🔐 ========= Daily Security Scans ========= 🔐\n\n"
echo "[💾] Disk space OK: ${available_gb}GB available"
echo "[•] Starting scans..."

# Initialize status files
for file in "${STATUS_FILES[@]}"; do 
  echo "FAIL" > "$file"
done

# Run scans in parallel
run_scan() {
  local tool=$1 
  local cmd=$2 
  local log=$3 
  local status=$4
  
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

# Enhanced analysis functions
analyze_rkhunter() {
  local log_file="$1"
  local warnings=0 
  local errors=0 
  local critical=0
  
  if [[ ! -s "$log_file" ]]; then
    echo "❌ No rkhunter output available"
    return
  fi
  
  if [[ -f "$log_file" ]]; then
    warnings=$(awk '/^Warning:/ {count++} END {print count+0}' "$log_file" 2>/dev/null || echo "0")
    errors=$(awk '/^Error:/ {count++} END {print count+0}' "$log_file" 2>/dev/null || echo "0")
  fi
  
  if grep -q -i 'rootkit\|backdoor\|trojan' "$log_file" 2>/dev/null; then
    critical=1
  fi
  
  echo "📊 RKHUNTER ANALYSIS:"
  echo "   • Warnings: $warnings"
  echo "   • Errors: $errors"
  echo "   • Critical Issues: $critical"
  
  if [[ $critical -gt 0 ]]; then
    echo "   🚨 CRITICAL: Potential malware detected!"
  fi
  
  if grep -q "replaced by a script" "$log_file" 2>/dev/null; then
    echo "   ⚠️  Script replacements detected (usually benign)"
  fi
  
  if grep -q "Hidden.*found" "$log_file" 2>/dev/null; then
    echo "   ⚠️  Hidden files/directories found"
  fi
  
  if grep -q "Suspicious file types" "$log_file" 2>/dev/null; then
    echo "   ⚠️  Suspicious file types in /dev (check if legitimate)"
  fi
  echo
}

analyze_lynis() {
  local log_file="$1"
  
  if [[ ! -s "$log_file" ]]; then
    echo "❌ No lynis output available"
    return
  fi
  
  local hardening_index=""
  if grep -q "Hardening index" "$log_file" 2>/dev/null; then
    hardening_index=$(grep "Hardening index" "$log_file" | tail -1 | awk '{print $NF}' | tr -d '[]')
  fi

  local suggestions=0 
  local warnings=0
  
  if [[ -f "$log_file" ]]; then
    suggestions=$(awk '/^- / {count++} END {print count+0}' "$log_file" 2>/dev/null || echo "0")
    warnings=$(awk '/WARNING/ {count++} END {print count+0}' "$log_file" 2>/dev/null || echo "0")
  fi
  
  echo "📊 LYNIS ANALYSIS:"
  if [[ -n "$hardening_index" ]]; then
    echo "   • Hardening Index: $hardening_index"
  fi
  echo "   • Suggestions: $suggestions"
  echo "   • Warnings: $warnings"

  if grep -q -i "authentication\|password\|ssh\|firewall" "$log_file" 2>/dev/null; then
    echo "   🔐 Security-related recommendations found"
  fi

  echo "   📋 Key Recommendations:"
  if grep -E "Suggestion|Consider|Install|Enable|Configure" "$log_file" >/dev/null 2>&1; then
    grep -E "Suggestion|Consider|Install|Enable|Configure" "$log_file" 2>/dev/null | head -3 | sed 's/^/      /' || echo "      Check full Lynis report for detailed recommendations"
  else
    echo "      Check full Lynis report for detailed recommendations"
  fi
  echo
}

analyze_chkrootkit() {
  local log_file="$1"

  if [[ ! -s "$log_file" ]]; then
    echo "❌ No chkrootkit output available"
    return
  fi

  local warnings=0
  local infected=0
  local suspicious=0

  if [[ -f "$log_file" ]]; then
    warnings=$(grep -c '^WARNING:' "$log_file" 2>/dev/null || echo "0")
    infected=$(grep -c 'INFECTED' "$log_file" 2>/dev/null || echo "0")
    suspicious=$(grep -c 'suspicious' "$log_file" 2>/dev/null || echo "0")
  fi

  echo "📊 CHKROOTKIT ANALYSIS:"
  echo "   • Warnings: $warnings"
  echo "   • Infected: $infected"
  echo "   • Suspicious: $suspicious"

  if [[ $infected -gt 0 ]]; then
    echo "   🚨 CRITICAL: Infections detected!"
  fi

  if grep -q "PACKET SNIFFER" "$log_file" 2>/dev/null; then
    echo "   🌐 Network sniffers detected:"
    grep "PACKET SNIFFER" "$log_file" 2>/dev/null | sed 's/^/      /' || true
    echo "      ℹ️  Check if these are legitimate (NetworkManager, Suricata, etc.)"
  fi

  local false_positives=0
  if [[ -f "$log_file" ]]; then
    false_positives=$(grep -c -E '\.document|\.gitignore|\.htaccess|\.build-id' "$log_file" 2>/dev/null || echo "0")
  fi
  if [[ $false_positives -gt 0 ]]; then
    echo "   ✅ Most suspicious files appear to be false positives ($false_positives)"
  fi
  echo
}

generate_summary() {
  local rk_status="$1" 
  local lynis_status="$2" 
  local chk_status="$3"
  
  echo "🎯 EXECUTIVE SUMMARY:"
  
  # Overall security posture
  if [[ "$rk_status" == "OK" && "$lynis_status" == "OK" && "$chk_status" == "OK" ]]; then
    echo "   ✅ GOOD: All security scans passed without issues"
  elif [[ "$rk_status" == "WARN" || "$lynis_status" == "WARN" || "$chk_status" == "WARN" ]]; then
    echo "   ⚠️  MODERATE: Some warnings detected, review recommended"
  else
    echo "   🚨 ATTENTION: Security scan failures detected, immediate review required"
  fi
  
  # Action items
  echo "   📋 RECOMMENDED ACTIONS:"
  
  if [[ "$rk_status" == "WARN" ]]; then
    echo "      • Review rkhunter warnings for legitimacy"
    echo "      • Update rkhunter database if needed: sudo rkhunter --update"
  fi
  
  if [[ "$lynis_status" != "OK" ]]; then
    echo "      • Review lynis suggestions for system hardening"
    echo "      • Consider implementing high-priority security recommendations"
  fi
  
  if [[ "$chk_status" == "WARN" ]]; then
    echo "      • Verify network sniffers are legitimate services"
    echo "      • Investigate any unexpected suspicious files"
  fi
  
  if [[ "$rk_status" == "FAIL" || "$lynis_status" == "FAIL" || "$chk_status" == "FAIL" ]]; then
    echo "      • Check system logs for errors"
    echo "      • Verify scanner installations and permissions"
  fi
  
  echo "      • Full logs available in: $LOG_DIR"
  echo
}

get_system_info() {
  echo "🖥️  SYSTEM INFORMATION:"
  echo "   • Hostname: $(hostname)"
  echo "   • Uptime: $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}')"
  echo "   • Load Average: $(cat /proc/loadavg | awk '{print $1,$2,$3}')"
  echo "   • Memory Usage: $(free -h | awk '/^Mem:/ {printf "%s/%s (%.1f%%)", $3, $2, ($3/$2)*100}')"
  echo "   • Disk Usage (root): $(df -h / | awk 'NR==2 {print $3"/"$2" ("$5")"}')"
  echo "   • Log Directory Space: ${available_gb}GB available"
  echo "   • Active Connections: $(ss -tuln | wc -l) listening ports"
  echo "   • Last Security Update: $(stat -c %y /var/log/apt/history.log 2>/dev/null | cut -d' ' -f1 || echo "Unknown")"
  echo
}

# Wait for all scans to complete and read results
echo "[⏳] Waiting for all scans to complete..."
scan_start_time=$(date +%s)

# Read status files into array
statuses=()
for status_file in "${STATUS_FILES[@]}"; do
  if [[ -f "$status_file" ]]; then
    statuses+=($(cat "$status_file"))
  else
    statuses+=("FAIL")
  fi
done

scan_end_time=$(date +%s)
scan_duration=$(( (scan_end_time - scan_start_time) / 60 ))
echo "[✅] All scans finished, generating report..."
echo ""

{
  echo "🔒 SECURITY SCAN REPORT - $HOSTNAME"
  echo "=================================================="
  echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  if [[ $scan_duration -gt 0 ]]; then
    echo "⏱️  Scan Duration: ${scan_duration} minutes"
  fi
  echo
  
  # Quick status overview
  printf "%-18s %s\n" "🛡 RKHUNTER:" "${statuses[0]}"
  printf "%-18s %s\n" "🔍 LYNIS:" "${statuses[1]}"  
  printf "%-18s %s\n" "🐛 CHKROOTKIT:" "${statuses[2]}"
  echo
  
  # Executive summary
  generate_summary "${statuses[0]}" "${statuses[1]}" "${statuses[2]}"
  
  # System information
  get_system_info
  
  # Detailed analysis
  echo "🔍 DETAILED ANALYSIS:"
  echo "=============================="
  analyze_rkhunter "${LOGS[0]}"
  analyze_lynis "${LOGS[1]}"
  analyze_chkrootkit "${LOGS[2]}"
  
  # Recent logs section (truncated for email)
  echo "📋 RECENT LOG EXCERPTS:"
  echo "=============================="
  
  for i in {0..2}; do
    tool_names=("RKHUNTER" "LYNIS" "CHKROOTKIT")
    echo "📄 ${tool_names[i]} (last 15 lines):"
    if [[ -s "${LOGS[i]}" ]]; then
      tail -n 15 "${LOGS[i]}" | sed 's/^/   /'
    else
      echo "   No output available"
    fi
    echo
  done
  
  # Footer
  echo "=============================="
  echo "📧 Generated by: enhanced_notify.sh"
  echo "📁 Full logs: $LOG_DIR"
  echo "🔧 GitHub: https://github.com/secure-linux-server"
  
} > "$REPORT"

# Determine email priority and subject
PRIORITY="Normal"
SUBJECT_PREFIX="[Security Scan]"

if [[ "${statuses[*]}" =~ "FAIL" ]]; then
  PRIORITY="High"
  SUBJECT_PREFIX="[URGENT Security Scan]"
elif [[ "${statuses[*]}" =~ "WARN" ]]; then
  PRIORITY="Medium"
  SUBJECT_PREFIX="[Warning Security Scan]"
fi

# Send email with proper headers
if command -v sendmail &> /dev/null; then
  {
    echo "To: $EMAIL"
    echo "Subject: $SUBJECT_PREFIX $HOSTNAME - $(date '+%Y-%m-%d %H:%M')"
    echo "X-Priority: $PRIORITY"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    cat "$REPORT"
  } | sendmail "$EMAIL"
  email_result=$?
else
  mail -s "$SUBJECT_PREFIX $HOSTNAME - $(date '+%Y-%m-%d %H:%M')" "$EMAIL" < "$REPORT"
  email_result=$?
fi

if [[ $email_result -eq 0 ]]; then
  echo "[📬] Enhanced email sent successfully"
else
  echo "[❌] Email failed to send"
fi

# Cleanup
rm -f "${STATUS_FILES[@]}" 2>/dev/null || true

# Summary output
echo ""
echo "📊 SCAN SUMMARY:"
echo "   RKHunter: ${statuses[0]}"
echo "   Lynis: ${statuses[1]}"
echo "   Chkrootkit: ${statuses[2]}"

# Exit with error if any scan failed
if [[ "${statuses[*]}" =~ "FAIL" ]]; then
  echo "[⚠️ ] One or more scans failed - check logs"
  exit 1
fi

echo "[🏁] Security scan completed successfully"