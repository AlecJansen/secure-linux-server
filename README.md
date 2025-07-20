# Secure Linux Server Toolkit

A lightweight hardening and monitoring toolkit for personal/home Ubuntu servers. Automates the setup of essential security tools, firewall rules, kernel hardening, and daily threat reports.

## Key Features

* UFW-based firewall initialization
* Fail2Ban brute-force SSH protection
* Rootkit and malware scanning: RKHunter, Chkrootkit, ClamAV
* Lynis system auditing
* Suricata IDS alert parsing (if installed)
* Email-based scan reports with `notify.sh`
* Optional kernel module blacklisting
* Interactive setup via `setup.sh`
* Log rotation, cron scheduling prompts, and update script

## Requirements

* Ubuntu/Debian-based system
* Internet connection
* `sudo` access

## Quick Start

```bash
git clone https://github.com/alecjansen/secure-linux-server.git
cd secure-linux-server
sudo ./setup.sh
```

The setup will:

* Prompt for system upgrade, tool installs, and hardening steps
* Configure and optionally run `lynis`, `rkhunter`, and `notify.sh`
* Configure `msmtp` for email alerts
* Offer to disable insecure kernel modules
* Summarize results in `~/secure-linux-server/setup-summary-<DATE>.txt`

## Daily Scan and Email Alerts

To configure daily security scans with email:

1. Ensure `msmtp` is installed and set up in `~/.msmtprc`.

   * Example config: [https://github.com/secure-linux-server/secure-linux-server/wiki/Email-Alerts](https://github.com/secure-linux-server/secure-linux-server/wiki/Email-Alerts)

2. Run `setup.sh` and provide your alert email when prompted.

3. Verify `notify.sh` was installed to:

   ```
   ~/secure-linux-server/alerts/scripts/notify.sh
   ```

4. Schedule a cron job (auto-prompted on first run), or manually:

   ```cron
   0 8 * * * bash $HOME/secure-linux-server/alerts/scripts/notify.sh --quick
   ```

The script:

* Runs `rkhunter`, `chkrootkit`, and `clamdscan` with resource limits
* Summarizes findings, includes Suricata alerts (if present)
* Emails a report (via `msmtp`) and logs everything to:

  ```
  ~/secure-linux-server/logs/
  ```

## Update Script

To regularly update system and security tools:

```bash
sudo ./update.sh
```

Performs:

* APT upgrade, autoremove, and cleanup
* Lynis update, ClamAV DB refresh
* RKHunter and Suricata rule updates (if present)
* Fail2Ban and UFW reloads
* Summary saved to `/var/log/secure-linux-server/`

## Optional Kernel Hardening

`setup.sh` offers optional disabling of risky or unused modules, like:

* `usb-storage`, `dccp`, `sctp`, `firewire-core`
* Config saved to: `/etc/modprobe.d/hardened-blacklist.conf`

## Directory Layout

```
secure-linux-server/
├── setup.sh            # Main interactive setup
├── update.sh           # Patch/update utility
├── alerts/scripts/notify.sh  # Daily scan/report script
├── logs/               # All generated logs
└── config/             # alert.conf stores your email
```

## Contributing

Pull requests are welcome! Focus on:

* Lightweight improvements
* Simplicity, performance, and clarity
* Avoiding dependencies unless strictly necessary

## License

MIT License

