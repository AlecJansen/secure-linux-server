#!/bin/bash

# setup.sh - Secure Linux Server Setup Script

set -e

echo "[*] Updating system..."
sudo apt update && sudo apt upgrade -y

echo "[*] Installing core tools..."
sudo apt install -y ufw fail2ban lynis rkhunter clamav unattended-upgrades mailutils msmtp

echo "[*] Enabling UFW and setting basic rules..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

echo "[*] Enabling and starting Fail2Ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "[*] Updating rkhunter file properties database (first time only)..."
sudo rkhunter --propupd -q

echo "[*] Updating ClamAV database..."
sudo freshclam

echo "[*] Creating log directory..."
mkdir -p "$HOME/secure-linux-server/logs"

echo "[*] Setting script permissions..."
chmod +x "$HOME/secure-linux-server/alerts/scripts/notify.sh"

echo "[✓] Setup complete. You can now run the scan with:"
echo "     ./alerts/scripts/notify.sh"
