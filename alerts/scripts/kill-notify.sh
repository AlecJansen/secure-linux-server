#!/bin/bash

# kill-notify.sh - Kill any active notify.sh scan processes

PATTERNS=(
  "rkhunter --check"
  "lynis audit system"
  "chkrootkit"
)

echo "[!] Searching for notify.sh scan processes to terminate..."

for pattern in "${PATTERNS[@]}"; do
  pids=$(pgrep -f "$pattern")
  if [[ -n "$pids" ]]; then
    echo "[*] Killing processes matching: $pattern"
    echo "$pids" | xargs sudo kill -9
  else
    echo "[✓] No active processes found for: $pattern"
  fi
done

echo "[✓] Scan process cleanup complete."
