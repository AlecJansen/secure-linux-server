#!/bin/bash

# Directory to store logs
LOG_DIR="$HOME/secure-linux-server/logs"

# Log files
RKHUNTER_LOG="$LOG_DIR/rkhunter.log"
LYNIS_LOG="$LOG_DIR/lynis-report.txt"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Clear previous logs or create new empty files
> "$RKHUNTER_LOG"
> "$LYNIS_LOG"

# Update rkhunter databases and run check
sudo rkhunter --check --rwo > "$RKHUNTER_LOG"
sudo rkhunter --check --sk --nocolors > "$LOG_DIR/rkhunter.log"


# Run lynis audit in cronjob mode
sudo lynis audit system --cronjob > "$LYNIS_LOG"

# Send email alerts (replace with your actual recipient email)
EMAIL="xc10397@aol.com"

cat "$RKHUNTER_LOG" | mail -s "Daily RKHunter Report" "$EMAIL"
cat "$LYNIS_LOG" | mail -s "Daily Lynis Report" "$EMAIL"
