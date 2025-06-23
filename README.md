# secure-linux-server
Active Linux Threat Monitoring & Response

This project helps harden and monitor a Linux server using tools like Fail2Ban, UFW, ClamAV, Lynis, rkhunter, and more. It includes custom scripts and configuration files for proactive system defense, alerting, and auditing.

## 📜 Contents

secure-linux-server/
├── README.md
├── LICENSE
├── setup.sh
├── fail2ban/
│ ├── jail.local
│ └── action.d/custom-email.conf
├── ufw/
│ └── rules.txt
├── alerts/
│ ├── email-alerts.md
│ ├── netdata-integration.md
│ └── scripts/
│ └── notify.sh
├── audits/
│ ├── lynis-report.txt
│ └── rkhunter.log
├── hardening/
│ ├── sysctl.conf
│ ├── sshd_config
│ └── ssh-hardening.md
└── tools/
└── clamav.md

## 🚀 Setup Script

The `setup.sh` script automates the configuration and hardening process. It includes:

- Internet connectivity and environment checks
- Required package installation (UFW, Fail2Ban, Lynis, ClamAV, etc.)
- Prompted activation for:
  - System upgrades
  - Firewall (UFW) with SSH allowlist
  - Fail2Ban (with optional jail.local config)
  - RKHunter and ClamAV initialization
  - Lynis system audit
  - Kernel module blacklisting (interactive)
  - Installation of `notify.sh` scan script
- Fail-safe prompts with default "no" behavior
- Log output saved to `~/secure-linux-server/setup-YYYY-MM-DD.log`

Run it with root privileges:
sudo ./setup.sh

🛡️ notify.sh: Daily Security Scanner
notify.sh runs RKHunter, chkrootkit, and ClamAV in parallel. It:

- Validates disk space and required binaries
- Logs findings to timestamped files
- Sends a consolidated summary report via email
- Cleans logs older than 14 days
- Resilient to partial scan failures

Schedule via cron for automated alerts:

~/secure-linux-server/alerts/scripts/notify.sh


✅ Features
- System Update & Hardened Defaults
- Firewall (UFW): Default deny, allow SSH
- Fail2Ban: Brute-force mitigation
- ClamAV: Up-to-date antivirus scanning
- RKHunter: Rootkit and malware check
- chkrootkit: Suspicious file & process scanner
- Lynis: Audit for config weaknesses
- Kernel Module Blacklisting: Disable unused and risky modules
- Logging & Email Alerts: Centralized scan logs, email reports
- Lightweight & Transparent: No bloat, fully open Bash scripts

📦 Installation

git clone https://github.com/alecjansen/secure-linux-server.git
cd secure-linux-server
chmod +x setup.sh
sudo ./setup.sh


🧾 Changelog

📄 Version 1.6.0
Enforced strict shell options (set -euo pipefail)

Line number trap on error

Logs setup process per day

Parallel scanning in notify.sh

Email handling improvements using mail/msmtp

Resilient disk space and scan result parsing

📄 Version 1.4.0
Added interactive kernel module blacklisting

Maintains /etc/modprobe.d/hardened-blacklist.conf

Added descriptions for each module

Improved fail2ban integration flow

🚀 Roadmap
 Automatic cron entry for notify.sh

 Optional anonymous telemetry

 Docker & WSL compatibility

 Basic HTML dashboard for alerts

🧠 Philosophy
Simple. Secure. Understandable.
Hardens your system transparently, keeping you informed without clutter or guesswork.

📬 License
MIT

PRs welcome. Star the project if you find it useful. Stay safe.

🛠️ Contributing
Fork and improve—whether it’s Netdata integration, log analysis, or better alerting UX.

