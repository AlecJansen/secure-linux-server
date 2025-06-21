#!/bin/bash

# notify-test.sh - Email-only version using existing logs

set -euo pipefail
umask 077

EMAIL="alecjansen1@gmail.com"
HOSTNAME="voyd"
LOG_DIR="$HOME/secure-linux-server/logs"
LATEST_RKHUNTER_LOG=$(ls -t "$LOG_DIR"/rkhunter_*.log | head -n 1)
LATEST_LYNIS_LOG=$(ls -t "$LOG_DIR"/lynis_*.log | head -n 1)
LATEST_CHKROOTKIT_LOG=$(ls -t "$LOG_DIR"/chkrootkit_*.log | head -n 1)
LATEST_WARNINGS=$(ls -t "$LOG_DIR"/chkrootkit_warnings_*.log | head -n 1)
DATE_TIME=$(date +%F_%H-%M-%S)
REPORT="$LOG_DIR/security-report-$DATE_TIME.txt"

# Color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
NC="\033[0m"

# Extract highlights
RKHUNTER_WARNINGS=$( [[ -s "$LATEST_RKHUNTER_LOG" ]] && grep -i 'warning:' "$LATEST_RKHUNTER_LOG" | head -n 10 || echo "None" )
CHKROOTKIT_WARNINGS=$( [[ -s "$LATEST_WARNINGS" ]] && grep -i 'warning:' "$LATEST_WARNINGS" | head -n 10 || echo "None" )
LYNIS_SUMMARY=$(awk '/\[ Lynis .* Results \]/{flag=1; print; next} /====/{flag=0} flag' "$LATEST_LYNIS_LOG")
[[ -z "$LYNIS_SUMMARY" ]] && LYNIS_SUMMARY="No summary block found, or Lynis output format changed."

# Compose report
{
  echo "========== Daily Security Report - $DATE_TIME =========="
  echo
  echo "🛡️ [ RKHunter Alerts ]"
  echo "$RKHUNTER_WARNINGS"
  echo
  echo "🔎 [ chkrootkit Highlights ]"
  echo "$CHKROOTKIT_WARNINGS"
  echo
  echo "📋 [ Lynis Summary ]"
  echo "$LYNIS_SUMMARY"
  echo
  echo "🔗 [ Logs Attached ]"
  echo "- Full Lynis Log: $LATEST_LYNIS_LOG"
  echo "- Full chkrootkit Log: $LATEST_CHKROOTKIT_LOG"
  echo "- Full rkhunter Log: $LATEST_RKHUNTER_LOG"
} > "$REPORT"

# Send email
SUBJECT="[SECURITY][$HOSTNAME] Manual Report Email - $DATE_TIME"
echo "[*] Sending report to $EMAIL..."
MAIL_OUTPUT=$(mktemp)
if mail -s "$SUBJECT" "$EMAIL" < "$REPORT" 2> "$MAIL_OUTPUT"; then
  echo -e "${GREEN}✓ Security report sent.${NC}"
else
  echo -e "${RED}✗ Failed to send security report. Details:${NC}"
  cat "$MAIL_OUTPUT"
fi
rm -f "$MAIL_OUTPUT"

echo "[✓] notify-test.sh completed on $HOSTNAME at $(date)"
