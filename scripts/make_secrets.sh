#!/bin/bash
# Generate login password, LUKS password, and SSH keypair

set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Specify a file to save generated secrets! Usage: $0 /path/to/output-folder" >&2
  exit 1
fi

out_dir="$1"

# Basic dependency checks
command -v openssl >/dev/null 2>&1 || { echo "Error: openssl is required." >&2; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { echo "Error: ssh-keygen is required." >&2; exit 1; }

mkdir -p "$out_dir"
chmod 700 "$out_dir"

login_pw_file="$out_dir/login_password.txt"
luks_pw_file="$out_dir/luks_password.txt"
ssh_key_file="$out_dir/id_ed25519"

# Generate random passwords (no trailing newline)
umask 077
openssl rand -base64 24 | tr -d '\n' > "$login_pw_file"
openssl rand -base64 48 | tr -d '\n' > "$luks_pw_file"

# Clear existing key file, and generate a new Ed25519 SSH keypair (empty passphrase)
rm -f "$ssh_key_file" "${ssh_key_file}.pub"
ssh-keygen -q -t ed25519 -N "" -f "$ssh_key_file" -C "ephemeral-$(date +%Y%m%d-%H%M%S)"

chmod 600 "$login_pw_file" "$luks_pw_file" "$ssh_key_file"
chmod 644 "$ssh_key_file.pub"

cat <<EOF
Done. Generated:
  Login password: $login_pw_file
  LUKS password:  $luks_pw_file
  SSH private key: $ssh_key_file
  SSH public key:  $ssh_key_file.pub
EOF

