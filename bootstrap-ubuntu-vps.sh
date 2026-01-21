#!/usr/bin/env bash
# bootstrap-ubuntu-vps.sh
# One-time root bootstrap: non-root sudo user, SSH harden, basic security + auto-tools

set -euo pipefail

# Check root
[ "$EUID" -ne 0 ] && echo "Run as root" && exit 1

# Detect container (e.g., Docker)
in_container() {
  grep -qE '(docker|lxc)' /proc/1/cgroup 2>/dev/null && return 0 || return 1
}

# ──────────────────────────────────────────────────────────────────────────────
# All interactive questions FIRST – before any package install or change
# ──────────────────────────────────────────────────────────────────────────────

echo "This script hardens a fresh Ubuntu VPS:"
echo "• creates non-root user"
echo "• disables root & password SSH login"
echo "• installs Fail2Ban, UFW, auto-updates, lynis, aide, clamav"
echo
echo "Continue? (y/N)"
read -r confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0

read -rp "New non-root username: " USERNAME
while [[ ! "$USERNAME" =~ ^[a-z][-a-z0-9_]*$ ]]; do
  echo "Invalid: must start with lowercase letter, then letters/digits/_/-"
  read -rp "New non-root username: " USERNAME
done

read -rsp "Password for $USERNAME (empty = random): " PASS
echo

read -rp "Enable passwordless sudo for $USERNAME? (y/N): " sudo_confirm

echo "Add SSH public key for $USERNAME:"
echo "  1) Paste now"
echo "  2) GitHub (gh:username)"
echo "  3) Launchpad (lp:username)"
echo "  4) Copy root's keys (fallback)"
read -rp "Choice [1-4]: " key_choice

key_input=""
gh_lp_user=""
prefix=""
case "$key_choice" in
  1)
    read -rp "Paste public key: " key_input
    ;;
  2|3)
    prefix=$([[ $key_choice == 2 ]] && echo "gh:" || echo "lp:")
    read -rp "Enter username: " gh_lp_user
    ;;
  4) ;;
  *) echo "No keys added." ;;
esac

read -rp "Add Pangolin UDP ports (51820/udp + 21820/udp) to UFW? (y/N): " add_pangolin

read -rp "Enable UFW after configuration? (y/N): " enable_ufw

# ──────────────────────────────────────────────────────────────────────────────
# Now start actual work
# ──────────────────────────────────────────────────────────────────────────────

install_packages() {
  apt update -qq || { echo "apt update failed"; exit 1; }
  DEBIAN_FRONTEND=noninteractive apt install -yq \
    fail2ban ufw unattended-upgrades ssh-import-id lynis aide clamav || { echo "Package install failed"; exit 1; }
  apt purge -y postfix >/dev/null 2>&1 || true
  if ! in_container; then
    systemctl disable --now postfix >/dev/null 2>&1 || true
  fi
}

create_user() {
  id "$USERNAME" &>/dev/null && { echo "❌ User $USERNAME exists"; exit 1; }

  useradd --create-home --shell /bin/bash -c "" "$USERNAME" || { echo "useradd failed"; exit 1; }
  usermod -aG sudo "$USERNAME" || { echo "usermod failed"; exit 1; }

  if [[ -z "$PASS" ]]; then
    command -v openssl >/dev/null || { echo "openssl missing"; exit 1; }
    PASS=$(openssl rand -base64 36) || { echo "openssl rand failed"; exit 1; }
    echo "Generated random password (SSH disabled): $PASS"
  fi
  echo "$USERNAME:$PASS" | chpasswd || { echo "chpasswd failed"; exit 1; }
}

enable_passwordless_sudo() {
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" || { echo "sudoers file failed"; exit 1; }
  chmod 0440 "/etc/sudoers.d/$USERNAME"
  visudo -cf "/etc/sudoers.d/$USERNAME" || { rm -f "/etc/sudoers.d/$USERNAME"; echo "visudo failed"; exit 1; }
}

setup_ssh_keys() {
  local homedir="/home/$USERNAME"
  local sshdir="$homedir/.ssh"
  local authkeys="$sshdir/authorized_keys"

  mkdir -p "$sshdir" || { echo "mkdir .ssh failed"; exit 1; }
  chown "$USERNAME:$USERNAME" "$sshdir" || { echo "chown .ssh dir failed"; exit 1; }
  chmod 700 "$sshdir"

  case "$key_choice" in
    1)
      echo "$key_input" > "$authkeys" || { echo "write authorized_keys failed"; exit 1; }
      ;;
    2|3)
      su - "$USERNAME" -c "ssh-import-id ${prefix}${gh_lp_user}" || { echo "ssh-import-id failed"; exit 1; }
      ;;
    4)
      cp /root/.ssh/authorized_keys "$authkeys" 2>/dev/null || true
      ;;
    *)
      echo "No keys added."
      return 0
      ;;
  esac

  # Now safe: file exists and is owned by user
  chown "$USERNAME:$USERNAME" "$authkeys" 2>/dev/null
  chmod 600 "$authkeys" 2>/dev/null || { echo "chmod authorized_keys failed"; exit 1; }
}

harden_ssh() {
  local cfg="/etc/ssh/sshd_config"
  sed -Ei 's/^#?(PermitRootLogin).*/\1 no/' "$cfg" || { echo "sed PermitRootLogin failed"; exit 1; }
  sed -Ei 's/^#?(PasswordAuthentication).*/\1 no/' "$cfg" || { echo "sed PasswordAuthentication failed"; exit 1; }
  sed -Ei 's/^#?(UsePAM).*/\1 no/' "$cfg" || { echo "sed UsePAM failed"; exit 1; }
  rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null

  sshd -t || { echo "sshd config invalid"; exit 1; }
  if ! in_container; then
    systemctl restart ssh || { echo "ssh restart failed"; exit 1; }
  fi
}

configure_ufw() {
  ufw --force reset >/dev/null || { echo "ufw reset failed"; exit 1; }
  ufw default deny incoming || { echo "ufw default deny failed"; exit 1; }
  ufw default allow outgoing || { echo "ufw default allow failed"; exit 1; }

  ufw allow 22/tcp || { echo "ufw allow 22 failed"; exit 1; }
  ufw allow 80/tcp || { echo "ufw allow 80 failed"; exit 1; }
  ufw allow 443/tcp || { echo "ufw allow 443 failed"; exit 1; }

  if [[ "$add_pangolin" == "y" || "$add_pangolin" == "Y" ]]; then
    ufw allow 51820/udp || { echo "ufw allow 51820 failed"; exit 1; }
    ufw allow 21820/udp || { echo "ufw allow 21820 failed"; exit 1; }
  fi

  echo "Final UFW rules:"
  ufw status

  if [[ "$enable_ufw" == "y" || "$enable_ufw" == "Y" ]]; then
    ufw --force enable || { echo "ufw enable failed"; exit 1; }
  else
    echo "UFW configured but NOT enabled. Run 'sudo ufw enable' later."
  fi
}

enable_auto_updates() {
  echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections || { echo "debconf-set-selections failed"; exit 1; }
  dpkg-reconfigure -f noninteractive unattended-upgrades || { echo "dpkg-reconfigure failed"; exit 1; }
  if ! in_container; then
    systemctl enable --now unattended-upgrades || { echo "unattended-upgrades enable failed"; exit 1; }
  fi
}

configure_extra_tools() {
  cat > /home/$USERNAME/first-login.sh <<'EOF'
#!/usr/bin/env bash

echo "Initializing AIDE database..."
sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db

if [ $? -eq 0 ]; then
  echo "AIDE initialized successfully."
  # Remove the line we added to .bashrc
  sed -i '/first-login.sh/d' ~/.bashrc
  rm -f "$0"
  echo "first-login.sh completed and removed."
else
  echo "AIDE init failed. Check logs and try again manually."
fi
EOF

  chown $USERNAME:$USERNAME /home/$USERNAME/first-login.sh
  chmod 755 /home/$USERNAME/first-login.sh

  # Append one-time execution line to .bashrc
  echo "# One-time AIDE init - remove after running" >> /home/$USERNAME/.bashrc
  echo "[ -f ~/first-login.sh ] && ~/first-login.sh" >> /home/$USERNAME/.bashrc

  chown $USERNAME:$USERNAME /home/$USERNAME/.bashrc

  cat > /etc/cron.daily/lynis-audit <<'EOF'
#!/bin/sh
/usr/sbin/lynis audit system --cronjob --quiet >> /var/log/lynis-daily.log 2>&1
EOF
  chmod +x /etc/cron.daily/lynis-audit

  if ! in_container; then
    systemctl enable --now clamav-freshclam 2>/dev/null || { echo "clamav-freshclam enable failed"; exit 1; }
  fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Execution
# ──────────────────────────────────────────────────────────────────────────────

install_packages
create_user
[[ "$sudo_confirm" == "y" || "$sudo_confirm" == "Y" ]] && enable_passwordless_sudo
setup_ssh_keys
harden_ssh
configure_ufw
enable_auto_updates
configure_extra_tools

echo "Done. Log out and reconnect as $USERNAME."
echo "On first login ~/first-login.sh runs automatically to initialize AIDE (self-deletes after success)."