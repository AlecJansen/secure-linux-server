# Secure Linux Server

This project automates the initial hardening and monitoring setup for a personal or home-based Ubuntu server. It includes firewall configuration, security tools, scheduled scan alerts, and optional kernel module lockdown.

## Features

* UFW firewall configuration
* Fail2Ban setup for SSH brute-force protection
* Rootkit and malware scanners: RKHunter, Chkrootkit, ClamAV
* Lynis security auditing
* Daily email reports via `notify.sh`
* Optional kernel module blacklist for hardening
* Interactive `setup.sh` with logging and summary

## Prerequisites

* Ubuntu/Debian-based system
* Internet connection
* Run `setup.sh` with `sudo` or as root

## Setup

Clone the repository:

```
git clone https://github.com/alecjansen/secure-linux-server.git
cd secure-linux-server
```

Run the setup:

```
sudo ./setup.sh
```

The script will:

* Prompt for actions (system upgrade, firewall rules, scan tool setup)
* Install essential packages:

  * `ufw`, `fail2ban`, `lynis`, `rkhunter`, `chkrootkit`, `clamav`, `clamav-daemon`, `unattended-upgrades`, `mailutils`, `msmtp`
* Configure `msmtp` as the default MTA if available
* Optionally copy `jail.local` for Fail2Ban if present
* Offer to run Lynis audit
* Prompt to install `notify.sh`
* Optionally blacklist unused/risky kernel modules

## Daily Scan and Notification

To set up daily email alerts:

1. Ensure `msmtp` is configured in `~/.msmtprc`
2. Edit your email in `alerts/scripts/notify.sh`
3. Add a cron job:

   crontab -e

Add the following line:

```
0 6 * * * $HOME/secure-linux-server/alerts/scripts/notify.sh
```

The script:

* Runs `rkhunter`, `chkrootkit`, and `clamdscan` with timeout, low IO priority
* Logs results to `~/secure-linux-server/logs/`
* Cleans logs older than 14 days
* Sends a unified report to your email with tool statuses and relevant findings

## Kernel Module Blacklisting

`setup.sh` allows optional disabling of risky or unused kernel modules (e.g., `usb-storage`, `dccp`, `sctp`). This adds entries to `/etc/modprobe.d/hardened-blacklist.conf`.

## Logs

All logs are saved in:

```
~/secure-linux-server/logs/
```

## Contributions

Pull requests and issues welcome. Lightweight, security-conscious additions are preferred.

## License

MIT License

