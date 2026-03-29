#!/bin/bash

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  $0 --old-password-file <path> --new-password-file <path> [--clevis-policy-file <path> | --clevis-policy <json>] [--device /dev/sda3]

Examples:
  $0 --old-password-file ./old.pw --new-password-file ./new.pw --clevis-policy-file ./config/tang.json
  $0 --old-password-file ./old.pw --new-password-file ./new.pw --clevis-policy '{"t":1,"pins":{"tang":[{"url":"http://tang.local"}]}}'

Notes:
  - Prefer --clevis-policy-file so callers do NOT need shell quoting.
  - See config/tang.json for a policy example.
EOF
  exit 1
}

device="/dev/sda3"
old_pw_file=""
new_pw_file=""
clevis_policy=""
clevis_policy_file=""
log_file="log.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device)
      [[ $# -ge 2 ]] || usage
      device="$2"
      shift 2
      ;;
    --old-password-file)
      [[ $# -ge 2 ]] || usage
      old_pw_file="$2"
      shift 2
      ;;
    --new-password-file)
      [[ $# -ge 2 ]] || usage
      new_pw_file="$2"
      shift 2
      ;;
    --clevis-policy)
      [[ $# -ge 2 ]] || usage
      clevis_policy="$2"
      shift 2
      ;;
    --clevis-policy-file)
      [[ $# -ge 2 ]] || usage
      clevis_policy_file="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$old_pw_file" ]] || { echo "Error: --old-password-file is required." >&2; usage; }
[[ -n "$new_pw_file" ]] || { echo "Error: --new-password-file is required." >&2; usage; }

[[ -r "$old_pw_file" ]] || { echo "Error: old password file not readable: $old_pw_file" >&2; exit 1; }
[[ -r "$new_pw_file" ]] || { echo "Error: new password file not readable: $new_pw_file" >&2; exit 1; }

# Require exactly one policy input mode.
if [[ -n "$clevis_policy" && -n "$clevis_policy_file" ]]; then
  echo "Error: use only one of --clevis-policy or --clevis-policy-file." >&2
  exit 1
fi

if [[ -z "$clevis_policy" && -z "$clevis_policy_file" ]]; then
  echo "Error: one of --clevis-policy or --clevis-policy-file is required." >&2
  exit 1
fi

if [[ -n "$clevis_policy_file" ]]; then
  [[ -r "$clevis_policy_file" ]] || { echo "Error: clevis policy file not readable: $clevis_policy_file" >&2; exit 1; }
  if command -v jq >/dev/null 2>&1; then
    clevis_policy="$(jq -c . "$clevis_policy_file")"
  else
    # Fallback: remove newlines so it becomes one argument string
    clevis_policy="$(tr -d '\n' < "$clevis_policy_file")"
  fi
fi

echo "Changing LUKS key on $device..." | tee -a "$log_file"
sudo cryptsetup luksChangeKey "$device" -d "$old_pw_file" "$new_pw_file"

echo "Changing LUKS Volume Key (slow) on $device..." | tee -a "$log_file"
sudo cryptsetup reencrypt "$device" -d "$new_pw_file" --key-slot 0

echo "Enabling Clevis policy-based decryption on $device..." | tee -a "$log_file"
sudo clevis luks bind -y -d "$device" -k "$new_pw_file" sss "$clevis_policy"

echo "Done." | tee -a "$log_file"

