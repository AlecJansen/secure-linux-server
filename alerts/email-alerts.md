📡 Email Alerts Setup (Gmail + msmtp)
This guide explains how to configure msmtp to send email alerts from your Linux server using a Gmail account. It's integrated with Fail2Ban for real-time notifications about bans and suspicious login attempts.

✅ Requirements
A Gmail account with App Passwords enabled.
msmtp and mailutils installed on the system.

🛠️ Installation & Configuration
Install msmtp and mail utilities:
sudo apt update
sudo apt install msmtp msmtp-mta mailutils
Create ~/.msmtprc with the following:
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           alecjansen1@gmail.com
user           alecjansen1@gmail.com
password       your_app_password_here

account default : gmail
Secure the config file:
chmod 600 ~/.msmtprc
Test email delivery:
echo "Test email from secure server" | mail -s "TEST ALERT" your-other-email@gmail.com

🔐 Fail2Ban Integration
Create custom action file
File: /etc/fail2ban/action.d/custom-email.conf
[Definition]
actionstart = echo "[Fail2Ban] Jail started: <name>" | mail -s "[Fail2Ban] <name> Started" alecjansen1@gmail.com
actionstop  = echo "[Fail2Ban] Jail stopped: <name>" | mail -s "[Fail2Ban] <name> Stopped" alecjansen1@gmail.com
actionban   = echo "[Fail2Ban] Banned IP <ip> from <name>" | mail -s "[Fail2Ban] <name>: Banned <ip>" alecjansen1@gmail.com
actionunban = echo "[Fail2Ban] Unbanned IP <ip> from <name>" | mail -s "[Fail2Ban] <name>: Unbanned <ip>" alecjansen1@gmail.com
Update jail configuration:
File: /etc/fail2ban/jail.local
[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log
backend = systemd
action  = custom-email
Restart Fail2Ban:
sudo systemctl restart fail2ban

📋 Logs & Debugging
Check ~/.msmtp.log for delivery issues.
Run fail2ban-client status to check jails.
