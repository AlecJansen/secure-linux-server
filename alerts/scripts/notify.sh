#!/bin/bash

# notify.sh - Daily security scan and email notifier

set -e

EMAIL="your@email.com"  # <-- replace with your email
LOG_DIR="$HOME/secure-linux-server/logs"
RKHUNTER_LOG="$LOG_DIR/rkhunter.log"
LYNIS_LOG="$LOG_DIR/lynis-report.txt"
CHKROOTKIT_LOG="$LOG_DIR/chkrootkit.log"
CHKROOTKIT_WARNINGS="$LOG_DIR/chkrootkit_warnings.txt"

mkdir -p "$LOG_DIR"

# Clear previous logs
: > "$RKHUNTER_LOG"
: > "$LYNIS_LOG"

### Run rkhunter
echo "Starting rkhunter scan..."
sudo rkhunter --check --rwo --quiet --nocolors > "$RKHUNTER_LOG" 2>&1
echo "rkhunter scan complete."

### Run lynis
echo "Starting lynis scan..."
sudo lynis audit system --cronjob > "$LYNIS_LOG" 2>&1
echo "lynis scan complete."

### Extract Lynis summary block
LYNIS_SUMMARY_BLOCK=$(awk '/\[ Lynis .* Results \]/{flag=1; print; next} /====/{flag=0} flag' "$LYNIS_LOG")

# Fallback if no summary block found
if [[ -z "$LYNIS_SUMMARY_BLOCK" ]]; then
  LYNIS_SUMMARY_BLOCK="No summary block found, or Lynis output format changed."
fi

### Email RKHunter full log
cat "$RKHUNTER_LOG" | mail -s "Daily RKHunter Report" "$EMAIL" \
  && echo "RKHunter report emailed successfully" \
  || echo "Failed to email RKHunter report"

### Email Lynis report with summary
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

### Run chkrootkit
echo "Starting chkrootkit scan..."
sudo chkrootkit > "$CHKROOTKIT_LOG" 2>&1
echo "chkrootkit scan complete."

### Extract and email chkrootkit warnings
grep -i "WARNING:" "$CHKROOTKIT_LOG" > "$CHKROOTKIT_WARNINGS" || true

if [[ -s "$CHKROOTKIT_WARNINGS" ]]; then
  mail -s "Daily chkrootkit Warnings" "$EMAIL" < "$CHKROOTKIT_WARNINGS"
  echo "chkrootkit warnings emailed"
else
  echo "No chkrootkit warnings found, skipping email."
fi
