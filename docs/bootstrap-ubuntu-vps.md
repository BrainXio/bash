# Bootstrap Ubuntu VPS Script

## Overview
`bootstrap-ubuntu-vps.sh` is a one-time root-run bootstrap script for fresh Ubuntu VPS.  
It:
- Creates non-root sudo user (optional passwordless sudo)
- Hardens SSH (disables root login + password auth)
- Installs & configures: Fail2Ban, UFW, unattended-upgrades, lynis, aide, clamav
- Asks all interactive questions **before** any changes
- Offers optional Pangolin UDP ports (51820/udp, 21820/udp) in UFW
- Creates `~/first-login.sh` that auto-runs on first login to initialize AIDE (self-deletes after success)

## Prerequisites
- Fresh Ubuntu 22.04 / 24.04 LTS VPS
- Root SSH access
- SSH public key ready (paste, GitHub, Launchpad or root fallback)
- Cloud provider firewall restricts SSH to your IP

## Usage

Run as root. Recommended method (interactive prompts require terminal):

### Download & Run Locally
```bash
cd /tmp
wget https://raw.githubusercontent.com/brainxio/bash/main/bootstrap-ubuntu-vps.sh
chmod +x bootstrap-ubuntu-vps.sh
./bootstrap-ubuntu-vps.sh
```

**Do not** pipe directly to bash (`curl | bash`) — it skips all prompts.

## Prompts (in order)
1. Confirm execution
2. New username
3. Password (empty = random)
4. Passwordless sudo? (y/N)
5. SSH key method (1=paste, 2=GitHub, 3=Launchpad, 4=root keys)
6. Add Pangolin UDP ports? (y/N)
7. Enable UFW after setup? (y/N)

## After Completion
- Log out
- Reconnect as new user  
  → `~/first-login.sh` runs automatically on first login to initialize AIDE  
  → Script self-deletes + removes itself from `.bashrc` after success

## Packages

| Package              | Purpose                                      |
|----------------------|----------------------------------------------|
| fail2ban            | Brute-force protection (mainly SSH)          |
| ufw                 | Simple firewall (rules for 22/80/443 + optional Pangolin UDP) |
| unattended-upgrades | Automatic security package updates           |
| ssh-import-id       | Fetch SSH keys from GitHub/Launchpad         |
| lynis               | Security auditing (daily cron)               |
| aide                | File integrity monitoring (auto-init on first login) |
| clamav              | Antivirus (freshclam daemon auto-updates)    |

## Security Notes
- All questions asked **before** any install/config change
- SSH password auth fully disabled after run
- Random password shown only if generated (for first sudo unless passwordless)
- UFW essentials (22/80/443) always added; Pangolin ports optional
- Test new user SSH login **before** closing root session
- ClamAV freshclam, lynis daily cron, unattended-upgrades enabled automatically