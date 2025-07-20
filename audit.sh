#!/bin/bash

# audit.sh - Lightweight Security Audit Script for Secure Linux Server

set -euo pipefail
umask 077

# Directories and Files
LOG_DIR="$HOME/secure-linux-server/logs/audits"
TIMESTAMP=$(date +%F_%H-%M-%S)
REPORT="$LOG_DIR/audit-report-$TIMESTAMP.txt"
mkdir -p "$LOG_DIR"

# Header
{
  echo "🔍 Security Audit Report - $TIMESTAMP"
  echo "============================================"
  echo "Hostname: $(hostname)"
  echo "Kernel: $(uname -r)"
  echo "Uptime: $(uptime -p)"
  echo "Date: $(date)"
  echo "============================================"
  echo ""
} > "$REPORT"

# Package Integrity
{
  echo "🔐 Package Integrity Check (dpkg)"
  echo "---------------------------------"
  sudo debsums -s 2>/dev/null || echo "debsums not installed"
  echo ""
} >> "$REPORT"

# Lynis Audit
{
  echo "🧪 Lynis Audit"
  echo "--------------"
  if command -v lynis &>/dev/null; then
    sudo lynis audit system --quiet --logfile "$LOG_DIR/lynis-$TIMESTAMP.log" | tee -a "$REPORT"
  else
    echo "Lynis not installed"
  fi
  echo ""
} >> "$REPORT"

# Fail2Ban Status
{
  echo "🚨 Fail2Ban Status"
  echo "------------------"
  if systemctl is-active --quiet fail2ban && command -v fail2ban-client &>/dev/null; then
    sudo fail2ban-client status
  else
    echo "Fail2Ban is not running"
  fi
  echo ""
} >> "$REPORT"

# UFW Rules
{
  echo "🛡️ UFW Firewall Rules"
  echo "----------------------"
  if command -v ufw &>/dev/null; then
    sudo ufw status verbose
  else
    echo "UFW not installed"
  fi
  echo ""
} >> "$REPORT"

# SSH Hardening Review
{
  echo "🔑 SSH Config Review"
  echo "---------------------"
  SSH_CONFIG="/etc/ssh/sshd_config"
  grep -Ei 'PermitRootLogin|PasswordAuthentication|MaxAuthTries|Port' "$SSH_CONFIG" || echo "Cannot read SSH config"
  echo ""
} >> "$REPORT"

# Auth Log Summary
{
  echo "📜 Recent Auth Log Entries"
  echo "---------------------------"
  sudo journalctl -u ssh --since "-1d" | tail -n 30 || echo "No recent SSH logins or journalctl unavailable"
  echo ""
} >> "$REPORT"

# Open Ports
{
  echo "🌐 Listening Network Ports"
  echo "---------------------------"
  sudo ss -tulnp | grep -v "127.0.0.1" || echo "No external listening ports found"
  echo ""
} >> "$REPORT"

# Disk Usage
{
  echo "💽 Disk Usage"
  echo "--------------"
  df -hT | grep -vE '^tmpfs|^udev'
  echo ""
} >> "$REPORT"

chmod 600 "$REPORT"
echo "✅ Audit complete. Report saved to: $REPORT"
