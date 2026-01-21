# Bootstrap Ubuntu VPS Script

## Overview
`bootstrap-ubuntu-vps.sh` is a one-time bootstrap script for Ubuntu VPS. It creates a non-root sudo user, hardens SSH (disables root login, password auth), installs and configures security tools (Fail2Ban, UFW, unattended-upgrades, rkhunter, lynis, aide, clamav), sets up auto-updates, and adds firewall rules for ports 22/TCP, 80/TCP, 443/TCP, 51820/UDP, 21820/UDP.

## Prerequisites
- Fresh Ubuntu VPS (20.04+).
- Root access via SSH.
- SSH public key ready (for pasting or importing from GitHub/Launchpad).
- Cloud firewall restricts SSH to your IP.

## Usage
Run as root. Two methods:

### 1. Download and Run Locally
1. SSH as root.
2. Download: `wget https://raw.githubusercontent.com/brainxio/bash/main/bootstrap-ubuntu-vps.sh`
3. Make executable: `chmod +x bootstrap-ubuntu-vps.sh`
4. Run: `./bootstrap-ubuntu-vps.sh`
5. Follow prompts: username, password (optional random), SSH key method.
6. After completion, log out and reconnect as new user.
7. Post-setup: As new user, run `sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db` for AIDE initialization.

### 2. Run Directly from Repo (Web Location)
1. SSH as root.
2. Pipe to bash: `curl -sSL https://raw.githubusercontent.com/brainxio/bash/main/bootstrap-ubuntu-vps.sh | sudo bash`
3. Follow prompts as above.
4. Reconnect as new user.
5. Complete AIDE init as above.

## Security Notes
- Script generates/displays random password if none provided (for initial sudo; change later).
- SSH keys required; password auth disabled.
- Tools auto-configured: Fail2Ban (brute-force protection), UFW (firewall), unattended-upgrades (security patches), rkhunter/lynis/aide/clamav (scans/integrity/AV with cron jobs).
- Test new user login before closing root session.