#!/bin/bash
# notify.sh - Runs rkhunter and lynis scans, then emails the reports

LOG_DIR="$HOME/secure-linux-server/logs"
RKHUNTER_LOG="$LOG_DIR/rkhunter.log"
LYNIS_LOG="$LOG_DIR/lynis-report.txt"
EMAIL="xc10397@aol.com"

mkdir -p "$LOG_DIR"

# Clear previous logs
: > "$RKHUNTER_LOG"
: > "$LYNIS_LOG"

echo "Starting rkhunter scan..."
sudo rkhunter --check --rwo --quiet --nocolors > "$RKHUNTER_LOG" 2>&1
echo "rkhunter scan complete."

echo "Starting lynis scan..."
sudo lynis audit system --cronjob > "$LYNIS_LOG" 2>&1
echo "lynis scan complete."

echo "RKHunter log size:" $(stat -c%s "$RKHUNTER_LOG")
echo "Lynis log size:" $(stat -c%s "$LYNIS_LOG")

# Extract Lynis summary block
LYNIS_SUMMARY_BLOCK=$(awk '/\[ Lynis .* Results \]/{flag=1; print; next} /====/{flag=0} flag' "$LYNIS_LOG")

# Fallback if no summary block was found
if [[ -z "$LYNIS_SUMMARY_BLOCK" ]]; then
  LYNIS_SUMMARY_BLOCK="No summary block found, or Lynis output format changed."
fi

# Email RKHunter full log
cat "$RKHUNTER_LOG" | mail -s "Daily RKHunter Report" "$EMAIL" \
  && echo "RKHunter report emailed successfully" \
  || echo "Failed to email RKHunter report"

# Email Lynis report with summary
{
  echo "Lynis Scan Summary:"
  echo "-------------------"
  echo "$LYNIS_SUMMARY_BLOCK"
  echo
  echo "Full Lynis Log:"
  echo "--------------"
  cat "$LYNIS_LOG"
} | mail -s "Daily Lynis Report" "$EMAIL" \
  && echo "Lynis report emailed successfully" \
  || echo "Failed to email Lynis report"

CHKROOTKIT_LOG="$LOG_DIR/chkrootkit.log"
CHKROOTKIT_WARNINGS="$LOG_DIR/chkrootkit_warnings.txt"

echo "Starting chkrootkit scan..."
sudo chkrootkit > "$CHKROOTKIT_LOG" 2>&1
echo "chkrootkit scan complete."

# Extract warnings or critical messages
grep -i "WARNING:" "$CHKROOTKIT_LOG" > "$CHKROOTKIT_WARNINGS" || true

if [[ -s "$CHKROOTKIT_WARNINGS" ]]; then
  # If warnings exist, email them
  mail -s "Daily chkrootkit Warnings" "$EMAIL" < "$CHKROOTKIT_WARNINGS"
  echo "chkrootkit warnings emailed"
else
  echo "No chkrootkit warnings found, skipping email."
fi
