# secure-linux-server
Active Linux Threat Monitoring & Response

This project is designed to help harden and monitor a Linux server using tools like Fail2Ban, UFW, ClamAV, Lynis, rkhunter, and more. It includes custom scripts and configuration files to enhance server security and alerting.

## 📜 Contents

```
secure-linux-server/
├── README.md
├── LICENSE
├── setup.sh
├── fail2ban/
│   ├── jail.local
│   └── action.d/custom-email.conf
├── ufw/
│   └── rules.txt
├── alerts/
│   ├── email-alerts.md
│   ├── netdata-integration.md
│   └── scripts/
│       └── notify.sh
├── audits/
│   ├── lynis-report.txt
│   └── rkhunter.log
├── hardening/
│   ├── sysctl.conf
│   ├── sshd_config
│   └── ssh-hardening.md
└── tools/
    └── clamav.md
```

## 🚀 Setup Script

The `setup.sh` script automates the initial hardening and configuration of your Linux server. Here's what it currently does:

- Ensures required packages are installed (planned)
- Copies Fail2Ban configuration files to the appropriate directories
- Applies basic firewall rules (planned)
- Prepares the system for email and Netdata alert integration (coming soon)
- Designed to be run with `sudo` permissions: `sudo ./setup.sh`

> More functionality coming as this project grows!

## 🛠️ Contributing

Feel free to fork and expand. PRs are welcome!

## 📬 Alerts

We’ll soon implement:
- Email alerts via `msmtp`
- Netdata integration for real-time monitoring

Stay tuned, and star the repo if you like it :)





Changes and new features
_______________________
0.16/1 Added email alert integration - Configured server to send email alerts via Gmail and 'msmtp' for critical events like SSH bans using 'Fail2Ban'. All email alert configuration setps can be found in 'alerts/email-alerts.md'.

# Secure Linux Server Setup

**Version: 1.2.0**  
Last updated: June 1, 2025

This project automates hardening and monitoring for a Linux server using tools like `ufw`, `fail2ban`, `rkhunter`, `lynis`, and email alerts.


v1.0.0 – Initial setup with basic tools (ufw, fail2ban, rkhunter, lynis, etc.)
v1.1.0 – Added notify.sh script and email alerts
v1.2.0 – Added Lynis summaries in email, refactored logs and update behavior
v1.3.0 - Added chrootkit support

