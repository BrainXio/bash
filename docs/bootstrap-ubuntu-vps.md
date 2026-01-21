# Bootstrap Ubuntu VPS Script

## Overview
`bootstrap-ubuntu-vps.sh` is a one-time root-run bootstrap script for fresh Ubuntu VPS.  
It:
- Creates non-root sudo user (optional passwordless sudo)
- Hardens SSH (disables root login + password auth)
- Installs & configures: Fail2Ban, UFW, unattended-upgrades, lynis, aide, clamav
- Asks interactive questions **before** any changes
- Offers optional Pangolin UDP ports (51820/udp, 21820/udp) in UFW

## Prerequisites
- Fresh Ubuntu 22.04 / 24.04 LTS VPS
- Root SSH access
- SSH public key ready (paste, GitHub, Launchpad or root fallback)
- Cloud provider firewall already restricts SSH to your IP

## Usage

Run as root. Two methods:

### 1. Download & Run Locally
```bash
wget https://raw.githubusercontent.com/brainxio/bash/main/bootstrap-ubuntu-vps.sh
chmod +x bootstrap-ubuntu-vps.sh
./bootstrap-ubuntu-vps.sh
```

### 2. Run Directly (one-liner)
```bash
curl -sSL https://raw.githubusercontent.com/brainxio/bash/main/bootstrap-ubuntu-vps.sh | bash
```

## Prompts (in order)
1. Confirm execution
2. New username
3. Password (empty = random)
4. Passwordless sudo? (y/N)
5. Add Pangolin UDP ports? (y/N)
6. Enable UFW after setup? (y/N)
7. SSH key method (1=paste, 2=GitHub, 3=Launchpad, 4=root keys)

## After Completion
- Log out
- Reconnect as new user
- Initialize AIDE database:
  ```bash
  sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  ```

## Security Notes
- All questions asked **before** any package install or config change
- SSH password auth fully disabled after run
- Random password shown only if generated (needed for first sudo unless passwordless)
- UFW essentials (22/80/443) always added; Pangolin ports optional
- Test new user SSH login **before** closing root session
- ClamAV freshclam, lynis daily cron, unattended-upgrades enabled automatically