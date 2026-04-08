#!/bin/bash

set -euo pipefail

# ---------- Define Parameters ----------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPTS_DIR="$REPO_ROOT/scripts"
CONFIG_DIR="$REPO_ROOT/config"
KEYS_DIR="$REPO_ROOT/keys"
PAYLOAD_DIR="$REPO_ROOT/payload"
EPHEMERAL_DIR="$REPO_ROOT/ephemeral"

PACKAGES_FILE="$CONFIG_DIR/packages.list"
CLEVIS_POLICY_FILE="$CONFIG_DIR/tang.json"
BOOTSTRAP_PEERS_FILE="$CONFIG_DIR/garage-nodes.list"

ADD_DOCKER_REPO_SCRIPT="$SCRIPTS_DIR/add_repo_docker.sh"
ADD_TAILSCALE_REPO_SCRIPT="$SCRIPTS_DIR/add_repo_tailscale.sh"
INSTALL_SCRIPT="$SCRIPTS_DIR/install.sh"
CLEAR_SSH_SCRIPT="$SCRIPTS_DIR/clear_ssh_keys.sh"
CONFIGURE_SSH_SCRIPT="$SCRIPTS_DIR/configure_ssh_access.sh"
PERSONALISE_SCRIPT="$SCRIPTS_DIR/make_secrets.sh"
REKEY_LUKS_SCRIPT="$SCRIPTS_DIR/rekey_luks.sh"
EXPAND_SCRIPT="$SCRIPTS_DIR/expand.sh"
ADD_SERIAL_SCRIPT="$SCRIPTS_DIR/add_serial_port.sh"
REKEY_SSH_SCRIPT="$SCRIPTS_DIR/rekey_ssh_access.sh"

PERSONALISE_CONFIG_SCRIPT="$PAYLOAD_DIR/garage/personalise-config.sh"

OLD_LOGIN_PASSWORD_FILE="$EPHEMERAL_DIR/old_login_key.pw"
OLD_LUKS_PASSWORD_FILE="$EPHEMERAL_DIR/old_luks_key.pw"

TARGET_USER="${SUDO_USER:-}"

# ---------- Helper Functions ----------

trim_trailing_newlines() {
  local file="$1"
  local content
  content="$(<"$file")"
  printf '%s' "$content" > "$file"
  chmod 600 "$file"
}

# ---------- preflight checks ----------

[[ $EUID -eq 0 ]] || { echo "Error: run with sudo/root."; exit 1; }
[[ -n "$TARGET_USER" ]] || { echo "Error: could not determine target user from SUDO_USER."; exit 1; }

HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$HOME_DIR" ]] || { echo "Error: could not resolve home directory for $TARGET_USER"; exit 1; }
TARGET_GROUP="$(id -gn "$TARGET_USER")"

# Validate resolved repository layout directories
[[ -d "$SCRIPTS_DIR" ]] || { echo "Error: scripts directory missing: $SCRIPTS_DIR"; exit 1; }
[[ -d "$CONFIG_DIR" ]] || { echo "Error: config directory missing: $CONFIG_DIR"; exit 1; }
[[ -d "$KEYS_DIR" ]] || { echo "Error: keys directory missing: $KEYS_DIR"; exit 1; }
[[ -d "$PAYLOAD_DIR" ]] || { echo "Error: payload directory missing: $PAYLOAD_DIR"; exit 1; }

# Secrets are stored in EPHEMERAL_DIR; ensure it exists and is writable
mkdir -p "$EPHEMERAL_DIR"
[[ -d "$EPHEMERAL_DIR" ]] || { echo "Error: ephemeral directory missing/unusable: $EPHEMERAL_DIR"; exit 1; }
[[ -w "$EPHEMERAL_DIR" ]] || { echo "Error: ephemeral directory not writable: $EPHEMERAL_DIR"; exit 1; }

# Check that required files exist
for f in \
  "$ADD_DOCKER_REPO_SCRIPT" \
  "$ADD_TAILSCALE_REPO_SCRIPT" \
  "$INSTALL_SCRIPT" \
  "$CLEAR_SSH_SCRIPT" \
  "$CONFIGURE_SSH_SCRIPT" \
  "$PERSONALISE_SCRIPT" \
  "$REKEY_LUKS_SCRIPT" \
  "$EXPAND_SCRIPT" \
  "$ADD_SERIAL_SCRIPT" \
  "$REKEY_SSH_SCRIPT" \
  "$PERSONALISE_CONFIG_SCRIPT" \
  "$PACKAGES_FILE" \
  "$CLEVIS_POLICY_FILE" \
  "$BOOTSTRAP_PEERS_FILE"
do
  [[ -e "$f" ]] || { echo "Error: required file missing: $f"; exit 1; }
done

[[ -r "$OLD_LUKS_PASSWORD_FILE" ]] || { echo "Error: missing old LUKS key file: $OLD_LUKS_PASSWORD_FILE"; exit 1; }
trim_trailing_newlines "$OLD_LUKS_PASSWORD_FILE"

if [[ -r "$OLD_LOGIN_PASSWORD_FILE" ]]; then
  trim_trailing_newlines "$OLD_LOGIN_PASSWORD_FILE"
else
  echo "Warning: old login key file not found: $OLD_LOGIN_PASSWORD_FILE"
fi

# ---------- main ----------

echo "1) Generate ephemeral credentials + SSH key"
bash "$CLEAR_SSH_SCRIPT"
bash "$CLEAR_SSH_SCRIPT"
bash "$PERSONALISE_SCRIPT" "$EPHEMERAL_DIR"

echo "2) Change hostname to short random value"
NEW_HOSTNAME="n$(openssl rand -hex 6)"
hostnamectl set-hostname "$NEW_HOSTNAME"
printf '%s' "$NEW_HOSTNAME" > "$EPHEMERAL_DIR/hostname.txt"
chown "$TARGET_USER:$TARGET_GROUP" "$EPHEMERAL_DIR/hostname.txt"
chmod 600 "$EPHEMERAL_DIR/hostname.txt"

echo "3) Clear machine-id"
truncate -s0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "4) Change login password"
LOGIN_PASSWORD="$(cat "$EPHEMERAL_DIR/login_password.txt")"
printf '%s:%s\n' "$TARGET_USER" "$LOGIN_PASSWORD" | chpasswd

echo "5) Remove existing SSH keys and replace with generated key"
SSH_DIR="$HOME_DIR/.ssh"
install -d -m 700 -o "$TARGET_USER" -g "$TARGET_GROUP" "$SSH_DIR"
rm -f \
  "$SSH_DIR/id_rsa" "$SSH_DIR/id_rsa.pub" \
  "$SSH_DIR/id_dsa" "$SSH_DIR/id_dsa.pub" \
  "$SSH_DIR/id_ecdsa" "$SSH_DIR/id_ecdsa.pub" \
  "$SSH_DIR/id_ed25519" "$SSH_DIR/id_ed25519.pub" \
  "$SSH_DIR/id_xmss" "$SSH_DIR/id_xmss.pub"

install -m 600 -o "$TARGET_USER" -g "$TARGET_GROUP" "$EPHEMERAL_DIR/id_ed25519" "$SSH_DIR/id_ed25519"
install -m 644 -o "$TARGET_USER" -g "$TARGET_GROUP" "$EPHEMERAL_DIR/id_ed25519.pub" "$SSH_DIR/id_ed25519.pub"

echo "6) Generate authorized_keys"
# Start from repo keys, then also add generated ephemeral pub key
sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$REKEY_SSH_SCRIPT" --overwrite "$KEYS_DIR"
sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$REKEY_SSH_SCRIPT" "$EPHEMERAL_DIR"

echo "7) Add repos"
bash "$ADD_DOCKER_REPO_SCRIPT"
bash "$ADD_TAILSCALE_REPO_SCRIPT"

echo "8) Install required packages"
apt-get update
bash "$INSTALL_SCRIPT" "$PACKAGES_FILE"

echo "9) Replace LUKS volume key"
bash "$REKEY_LUKS_SCRIPT" \
  --old-password-file "$OLD_LUKS_PASSWORD_FILE" \
  --new-password-file "$EPHEMERAL_DIR/luks_password.txt" \
  --clevis-policy-file "$CLEVIS_POLICY_FILE"

echo "10) Expand disk (non-fatal)"
if bash "$EXPAND_SCRIPT"; then
  echo "Disk expansion step completed."
else
  echo "Warning: disk expansion failed or not required; continuing."
fi

echo "11) Set up serial port"
bash "$ADD_SERIAL_SCRIPT"

echo "12) Update initramfs"
update-initramfs -u -k 'all'

echo "13) Copy payload contents to home"
if [[ -d "$PAYLOAD_DIR" ]]; then
  shopt -s dotglob nullglob
  for item in "$PAYLOAD_DIR"/*; do
    cp -a "$item" "$HOME_DIR/"
  done
  shopt -u dotglob nullglob
  chown -R "$TARGET_USER:$TARGET_GROUP" "$HOME_DIR"
fi

# Allow target user to write secrets in EPHEMERAL_DIR
chown -R "$TARGET_USER:$TARGET_GROUP" "$EPHEMERAL_DIR"
chmod 700 "$EPHEMERAL_DIR"

# Hardening: ensure files are private
find "$EPHEMERAL_DIR" -type f -exec chmod 600 {} \;

sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$PERSONALISE_CONFIG_SCRIPT" \
  "$HOME_DIR/garage/vols/garage.toml" \
  "$EPHEMERAL_DIR" \
  "$BOOTSTRAP_PEERS_FILE" \
  "$PAYLOAD_DIR/garage/garage.template.toml"

# These are commended out to allow for configuration prior to running containers
# echo "14) docker compose up -d, then reboot"
# cd "$HOME_DIR/garage" && docker compose up -d
# cd "$HOME_DIR/garage" && docker exec garage-garage-1 /garage status

reboot
