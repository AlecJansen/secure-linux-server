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


**Version:** 1.4.0  
**Author:** AlecJansen

## 🔐 Overview
A lightweight, open-source bash framework to secure and harden a Linux server with minimal setup. Designed for sysadmins, hobbyists, and security-minded individuals.

## ✅ Features
- **System Updates & Hardened Defaults**
- **Firewall (UFW)**: Deny-all, allow SSH, block the rest
- **Fail2Ban**: Protects against brute-force attacks
- **ClamAV**: Antivirus scanner with latest definitions
- **RKHunter**: Rootkit detection
- **chkrootkit**: Suspicious file & process scanner
- **Lynis**: System config and audit hardening
- **Kernel Module Hardening**: Prompt-based disablement of risky modules (NEW)
- **Logging & Alerting**: Email-based daily reports with summaries and warnings
- **Lightweight & Transparent**: No daemons or proprietary blobs

## 📦 Installation
```bash
git clone https://github.com/alecjansen/secure-linux-server.git
cd secure-linux-server
chmod +x setup.sh
./setup.sh
```

## 🛡️ Daily Scanning & Alerts
Run this anytime or schedule with `cron`:
```bash
./alerts/scripts/notify.sh
```

## 📄 Version 1.4.0 Changes
- [x] Added interactive kernel module hardening prompt
- [x] User-friendly descriptions for each module
- [x] Maintains blacklist in `/etc/modprobe.d/hardened-blacklist.conf`
- [x] Refactored setup flow to include security context for choices

## 🚀 Roadmap
- Automatic cron integration (daily scans)
- Optional telemetry (anonymous opt-in logging)
- Docker/WSL support
- Web dashboard for report viewing

## 🧠 Philosophy
Simple. Open. Transparent. Harden your system in minutes, understand exactly what it’s doing.

## 📬 License
MIT

---
*Pull requests welcome. Stay safe out there.*



## 🛠️ Contributing

Feel free to fork and expand. PRs are welcome!

- Netdata integration for real-time monitoring

Stay tuned, and star the repo if you like it :)




