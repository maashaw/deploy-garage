#!/bin/bash

set -euo pipefail

# ---- Hardcoded paths / settings ----
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="/dev/sda3"

ADD_DOCKER_REPO_SCRIPT="$REPO_ROOT/add_repo_docker.sh"
INSTALL_SCRIPT="$REPO_ROOT/install.sh"
PERSONALISE_SCRIPT="$REPO_ROOT/personalise.sh"
REKEY_LUKS_SCRIPT="$REPO_ROOT/rekey_luks.sh"
ADD_SERIAL_SCRIPT="$REPO_ROOT/add_serial_port"
REKEY_SSH_SCRIPT="$REPO_ROOT/rekey.sh"
PERSONALISE_CONFIG_SCRIPT="$REPO_ROOT/personalise-config.sh"

PACKAGES_FILE="$REPO_ROOT/packages.list"
KEYS_DIR="$REPO_ROOT/keys"
PAYLOAD_DIR="$REPO_ROOT/payload"
CLEVIS_POLICY_FILE="$REPO_ROOT/config/tang.json"
BOOTSTRAP_PEERS_FILE="$REPO_ROOT/config/bootstrap_peers.txt"

EPHEMERAL_DIR="$REPO_ROOT/ephemeral"
OLD_LOGIN_PASSWORD_FILE="$EPHEMERAL_DIR/old_login_key.pw"
OLD_LUKS_PASSWORD_FILE="$EPHEMERAL_DIR/old_luks_key.pw"

TARGET_USER="${SUDO_USER:-}"
# ------------------------------------

trim_trailing_newlines() {
  local file="$1"
  local content
  content="$(<"$file")"
  printf '%s' "$content" > "$file"
  chmod 600 "$file"
}

[[ $EUID -eq 0 ]] || { echo "Error: run with sudo/root."; exit 1; }
[[ -n "$TARGET_USER" ]] || { echo "Error: could not determine target user from SUDO_USER."; exit 1; }

HOME_DIR="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$HOME_DIR" ]] || { echo "Error: could not resolve home directory for $TARGET_USER"; exit 1; }
TARGET_GROUP="$(id -gn "$TARGET_USER")"

for f in \
  "$ADD_DOCKER_REPO_SCRIPT" \
  "$INSTALL_SCRIPT" \
  "$PERSONALISE_SCRIPT" \
  "$REKEY_LUKS_SCRIPT" \
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

echo "1) Add Docker repo"
bash "$ADD_DOCKER_REPO_SCRIPT"

echo "2) Install required packages"
apt-get update
bash "$INSTALL_SCRIPT" "$PACKAGES_FILE"

echo "3) Generate ephemeral credentials + SSH key"
bash "$PERSONALISE_SCRIPT" "$EPHEMERAL_DIR"

echo "4) Replace LUKS volume key"
bash "$REKEY_LUKS_SCRIPT" \
  --device "$DEVICE" \
  --old-password-file "$OLD_LUKS_PASSWORD_FILE" \
  --new-password-file "$EPHEMERAL_DIR/luks_password.txt" \
  --clevis-policy-file "$CLEVIS_POLICY_FILE"

echo "5) Set up serial port"
bash "$ADD_SERIAL_SCRIPT"

echo "6) Update initramfs"
update-initramfs -u -k 'all'

echo "7) Change hostname to short random value"
NEW_HOSTNAME="n$(openssl rand -hex 6)"
hostnamectl set-hostname "$NEW_HOSTNAME"
printf '%s' "$NEW_HOSTNAME" > "$EPHEMERAL_DIR/hostname.txt"
chown "$TARGET_USER:$TARGET_GROUP" "$EPHEMERAL_DIR/hostname.txt"
chmod 600 "$EPHEMERAL_DIR/hostname.txt"

echo "8) Clear machine-id"
truncate -s0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -s /etc/machine-id /var/lib/dbus/machine-id

echo "9) Change login password"
LOGIN_PASSWORD="$(cat "$EPHEMERAL_DIR/login_password.txt")"
printf '%s:%s\n' "$TARGET_USER" "$LOGIN_PASSWORD" | chpasswd

echo "10) Remove existing SSH keys and replace with generated key"
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

echo "11) Generate authorized_keys"
# Start from repo keys, then also add generated ephemeral pub key
sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$REKEY_SSH_SCRIPT" --overwrite "$KEYS_DIR"
sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$REKEY_SSH_SCRIPT" "$EPHEMERAL_DIR"

echo "12) Move payload contents to home and personalise garage.toml"
if [[ -d "$PAYLOAD_DIR" ]]; then
  shopt -s dotglob nullglob
  for item in "$PAYLOAD_DIR"/*; do
    mv "$item" "$HOME_DIR/"
  done
  shopt -u dotglob nullglob
  chown -R "$TARGET_USER:$TARGET_GROUP" "$HOME_DIR"
fi

[[ -f "$HOME_DIR/garage.toml" ]] || { echo "Error: expected $HOME_DIR/garage.toml after payload move"; exit 1; }

sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash "$PERSONALISE_CONFIG_SCRIPT" \
  "$HOME_DIR/garage.toml" \
  "$EPHEMERAL_DIR" \
  "$BOOTSTRAP_PEERS_FILE" \
  "$HOME_DIR/garage.toml"

echo "13) docker-compose up -d, then reboot"
sudo -u "$TARGET_USER" -H HOME="$HOME_DIR" bash -lc "cd \"$HOME_DIR\" && (docker-compose up -d || docker compose up -d)"

reboot
