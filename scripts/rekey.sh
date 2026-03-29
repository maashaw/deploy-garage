#!/usr/bin/env bash

set -euo pipefail

usage() {
  echo "Usage: $0 [--overwrite] /path/to/keys-directory" >&2
  exit 1
}

overwrite=false

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
fi

if [[ "${1:-}" == "--overwrite" ]]; then
  overwrite=true
  shift
fi

[[ $# -eq 1 ]] || usage

keys_dir="$1"
auth_file="$HOME/.ssh/authorized_keys"

if [[ ! -d "$keys_dir" ]]; then
  echo "Error: not a directory: $keys_dir" >&2
  exit 1
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$auth_file"
chmod 600 "$auth_file"

if $overwrite; then
  : > "$auth_file"
fi

# Track what we already have to avoid duplicates.
declare -A seen=()

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "${line//[[:space:]]/}" ]] || continue
  seen["$line"]=1
done < "$auth_file"

added=0

# Recursively scan all files in keys_dir
while IFS= read -r -d '' file; do
  [[ -r "$file" ]] || continue

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -n "$line" ]] || continue
    [[ "$line" == \#* ]] && continue

    # Accept common OpenSSH public key formats.
    if [[ "$line" =~ ^(ssh-(rsa|ed25519|dss)|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
      if [[ -z "${seen[$line]+x}" ]]; then
        echo "$line" >> "$auth_file"
        seen["$line"]=1
        ((added++))
      fi
    fi
  done < "$file"
done < <(find "$keys_dir" -type f -print0)

echo "Done. Added $added key(s) to $auth_file"
