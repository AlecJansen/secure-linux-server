#!/bin/bash

# setup.sh - Secure Linux Server Setup Script

set -e

echo "[*] Updating system..."
sudo apt update && sudo apt upgrade -y

echo "[*] Installing core tools..."
sudo apt install -y ufw fail2ban lynis rkhunter clamav unattended-upgrades

echo "[*] Enabling UFW and setting basic rules..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

echo "[*] Enabling Fail2Ban..."
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

echo "[*] Updating rkhunter database..."
sudo rkhunter --update

echo "[*] Updating ClamAV database..."
sudo freshclam

echo "[*] System prep complete. Consider running: sudo lynis audit system"

