#!/usr/bin/env bash
# bootstrap-ubuntu-vps.sh
# One-time root bootstrap: non-root sudo user, SSH harden, basic security + auto-tools

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────────────────

readonly SSH_PORT=22
readonly UFW_ALLOWED_PORTS=(
  "22/tcp"
  "80/tcp"
  "443/tcp"
  "51820/udp"
  "21820/udp"
)

# ──────────────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────────────

install_packages() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -yq \
    fail2ban ufw unattended-upgrades ssh-import-id \
    rkhunter lynis aide clamav
}

create_user() {
  local username="$1"
  local password="${2:-}"

  if id "$username" &>/dev/null; then
    echo "❌ User $username already exists." >&2
    exit 1
  fi

  useradd --create-home --shell /bin/bash --gecos "" "$username"
  usermod -aG sudo "$username"

  if [[ -z "$password" ]]; then
    password=$(openssl rand -base64 36)
    echo "Generated random password (SSH disabled): $password"
  fi
  echo "${username}:${password}" | chpasswd
}

setup_ssh_keys() {
  local username="$1"
  local key_input choice prefix gh_lp_user

  mkdir -p "/home/$username/.ssh"
  chmod 700 "/home/$username/.ssh"

  echo "Add SSH public key:"
  echo "  1) Paste now"
  echo "  2) GitHub (gh:username)"
  echo "  3) Launchpad (lp:username)"
  echo "  4) Copy root's keys (fallback)"
  read -rp "Choice [1-4]: " choice

  case "$choice" in
    1)
      read -rp "Paste public key: " key_input
      echo "$key_input" > "/home/$username/.ssh/authorized_keys"
      ;;
    2|3)
      prefix=$([[ $choice == 2 ]] && echo "gh:" || echo "lp:")
      read -rp "Enter username: " gh_lp_user
      su - "$username" -c "ssh-import-id ${prefix}${gh_lp_user}"
      ;;
    4)
      cp /root/.ssh/authorized_keys "/home/$username/.ssh/authorized_keys" 2>/dev/null || true
      ;;
    *)
      echo "No keys added." >&2
      ;;
  esac

  chmod 600 "/home/$username/.ssh/authorized_keys" 2>/dev/null
  chown -R "$username:$username" "/home/$username/.ssh"
}

harden_ssh() {
  local cfg="/etc/ssh/sshd_config"
  local dropin="/etc/ssh/sshd_config.d/50-cloud-init.conf"

  sed -Ei 's/^#?(PermitRootLogin).*/\1 no/' "$cfg"
  sed -Ei 's/^#?(PasswordAuthentication).*/\1 no/' "$cfg"
  sed -Ei 's/^#?(UsePAM).*/\1 no/' "$cfg"

  [[ -f "$dropin" ]] && rm -f "$dropin"

  /usr/sbin/sshd -t || { echo "SSHD config invalid!"; exit 1; }
  systemctl restart ssh
}

configure_ufw() {
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  for p in "${UFW_ALLOWED_PORTS[@]}"; do
    ufw allow "$p"
  done

  ufw --force enable
}

enable_auto_updates() {
  dpkg-reconfigure --priority=low unattended-upgrades
  systemctl enable --now unattended-upgrades
}

configure_extra_tools() {
  echo "Post-setup: sudo aideinit && sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db"

  cat > /etc/cron.daily/lynis-audit <<'EOF'
#!/bin/sh
/usr/sbin/lynis audit system --cronjob --quiet >> /var/log/lynis-daily.log 2>&1
EOF
  chmod +x /etc/cron.daily/lynis-audit

  systemctl enable --now clamav-freshclam
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

install_packages

read -rp "New non-root username: " USERNAME
while [[ ! "$USERNAME" =~ ^[a-z][-a-z0-9_]*$ ]]; do
  echo "Invalid (lowercase start, letters/digits/_/-)"
  read -rp "New non-root username: " USERNAME
done

read -rsp "Password (empty = random): " PASS
echo

create_user "$USERNAME" "$PASS"
setup_ssh_keys "$USERNAME"
harden_ssh
configure_ufw
enable_auto_updates
configure_extra_tools

echo "Done. Reconnect as $USERNAME. Password auth disabled."
echo "Random password shown above (use for first sudo)."