#!/usr/bin/env bash
# bootstrap-ubuntu-vps.sh
# One-time root bootstrap: non-root sudo user, SSH harden, basic security + auto-tools

set -euo pipefail

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

read -rp "Add Pangolin UDP ports (51820/udp + 21820/udp) to UFW? (y/N): " add_pangolin

read -rp "Enable UFW after configuration? (y/N): " enable_ufw

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

# ──────────────────────────────────────────────────────────────────────────────
# Now start actual work
# ──────────────────────────────────────────────────────────────────────────────

install_packages() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -yq \
    fail2ban ufw unattended-upgrades ssh-import-id lynis aide clamav
  apt purge -y postfix >/dev/null 2>&1 || true
  systemctl disable --now postfix >/dev/null 2>&1 || true
}

create_user() {
  if id "$USERNAME" &>/dev/null; then
    echo "❌ User $USERNAME already exists." >&2
    exit 1
  fi

  useradd --create-home --shell /bin/bash -c "" "$USERNAME"
  usermod -aG sudo "$USERNAME"

  if [[ -z "$PASS" ]]; then
    PASS=$(openssl rand -base64 36)
    echo "Generated random password (SSH disabled): $PASS"
  fi
  echo "$USERNAME:$PASS" | chpasswd
}

enable_passwordless_sudo() {
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
  chmod 0440 "/etc/sudoers.d/$USERNAME"
  visudo -cf "/etc/sudoers.d/$USERNAME" || { rm -f "/etc/sudoers.d/$USERNAME"; exit 1; }
}

setup_ssh_keys() {
  mkdir -p "/home/$USERNAME/.ssh"
  chmod 700 "/home/$USERNAME/.ssh"

  case "$key_choice" in
    1) echo "$key_input" > "/home/$USERNAME/.ssh/authorized_keys" ;;
    2|3) su - "$USERNAME" -c "ssh-import-id ${prefix}${gh_lp_user}" ;;
    4) cp /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null || true ;;
    *) echo "No keys added." ;;
  esac

  chmod 600 "/home/$USERNAME/.ssh/authorized_keys" 2>/dev/null
  chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
}

harden_ssh() {
  local cfg="/etc/ssh/sshd_config"
  sed -Ei 's/^#?(PermitRootLogin).*/\1 no/' "$cfg"
  sed -Ei 's/^#?(PasswordAuthentication).*/\1 no/' "$cfg"
  sed -Ei 's/^#?(UsePAM).*/\1 no/' "$cfg"
  rm -f /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null

  sshd -t || { echo "sshd config invalid"; exit 1; }
  systemctl restart ssh
}

configure_ufw() {
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing

  # Essentials always
  ufw allow 22/tcp
  ufw allow 80/tcp
  ufw allow 443/tcp

  if [[ "$add_pangolin" == "y" || "$add_pangolin" == "Y" ]]; then
    ufw allow 51820/udp
    ufw allow 21820/udp
  fi

  echo "Final UFW rules:"
  ufw status

  if [[ "$enable_ufw" == "y" || "$enable_ufw" == "Y" ]]; then
    ufw --force enable
  else
    echo "UFW configured but NOT enabled. Run 'sudo ufw enable' later."
  fi
}

enable_auto_updates() {
  echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
  dpkg-reconfigure -f noninteractive unattended-upgrades
  systemctl enable --now unattended-upgrades
}

configure_extra_tools() {
  echo "After login run: sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db"

  cat > /etc/cron.daily/lynis-audit <<'EOF'
#!/bin/sh
/usr/sbin/lynis audit system --cronjob --quiet >> /var/log/lynis-daily.log 2>&1
EOF
  chmod +x /etc/cron.daily/lynis-audit

  systemctl enable --now clamav-freshclam 2>/dev/null
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