#!/bin/bash

set -euo pipefail

# finalise.sh
# Interactive post-init checklist:
# - Optional hostname change
# - Optional static IP configuration via netplan
# - Optional Caddyfile hostname update
# - Prints reminder checklist for other follow-up tasks

# ---------- helpers ----------

as_root() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-N}" # Y or N
  local reply

  while true; do
    if [[ "$default" == "Y" ]]; then
      read -r -p "$prompt [Y/n]: " reply
      reply="${reply:-Y}"
    else
      read -r -p "$prompt [y/N]: " reply
      reply="${reply:-N}"
    fi

    case "$reply" in
      Y|y|yes|YES) return 0 ;;
      N|n|no|NO)   return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

ask_with_default() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value
    echo "${value:-$default}"
  else
    read -r -p "$prompt: " value
    echo "$value"
  fi
}

validate_hostname_label() {
  local h="$1"
  # Linux hostname label style: letters/numbers/hyphen, not starting/ending with hyphen, max 63 chars
  [[ "$h" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]
}

detect_default_interface() {
  ip -o route show to default 2>/dev/null | awk '{print $5; exit}'
}

detect_first_site_label_from_caddyfile() {
  local file="$1"
  awk '
    /^[[:space:]]*#/ {next}
    /^[[:space:]]*$/ {next}
    {
      token=$1
      gsub(/[{},]/, "", token)
      print token
      exit
    }
  ' "$file"
}

# ---------- intro ----------

echo "=== Node finalisation wizard ==="
echo "This script has no mandatory parameters and is interactive."
echo

current_hostname="$(hostnamectl --static 2>/dev/null || hostname)"
echo "Current hostname: $current_hostname"
echo

new_hostname=""

# ---------- hostname ----------

if ask_yes_no "Do you want to set/update the hostname?" "N"; then
  while true; do
    candidate="$(ask_with_default "Enter hostname label (example: garage-nyc-048)")"
    if [[ -z "$candidate" ]]; then
      echo "Hostname cannot be empty."
      continue
    fi
    if ! validate_hostname_label "$candidate"; then
      echo "Invalid hostname label. Use letters, numbers, hyphens; max 63 chars; no leading/trailing hyphen."
      continue
    fi

    echo "Setting hostname to: $candidate"
    as_root hostnamectl set-hostname "$candidate"
    new_hostname="$candidate"
    echo "Hostname updated."
    break
  done
else
  echo "Skipping hostname update."
fi

echo

# ---------- static IP / netplan ----------

if ask_yes_no "Do you want to configure a static IP with netplan?" "N"; then
  if ! command -v netplan >/dev/null 2>&1; then
    echo "Error: netplan is not installed; skipping static IP configuration."
  else
    default_iface="$(detect_default_interface || true)"
    iface="$(ask_with_default "Network interface to configure" "${default_iface:-eth0}")"

    while true; do
      addr_cidr="$(ask_with_default "Static IPv4 address with CIDR (example: 192.168.10.48/24)")"
      if [[ "$addr_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
        break
      fi
      echo "Invalid format. Expected e.g. 192.168.10.48/24"
    done

    gateway4="$(ask_with_default "Gateway IPv4 (optional, example: 192.168.10.1)" "")"
    dns_csv="$(ask_with_default "DNS servers comma-separated (optional, example: 1.1.1.1,8.8.8.8)" "")"
    search_csv="$(ask_with_default "DNS search domains comma-separated (optional, example: example.com,corp.local)" "")"

    netplan_file="/etc/netplan/99-finalise-static.yaml"
    tmp_file="$(mktemp)"

    {
      echo "network:"
      echo "  version: 2"
      echo "  ethernets:"
      echo "    $iface:"
      echo "      dhcp4: false"
      echo "      addresses:"
      echo "        - $addr_cidr"

      if [[ -n "$gateway4" ]]; then
        echo "      routes:"
        echo "        - to: default"
        echo "          via: $gateway4"
      fi

      if [[ -n "$dns_csv" || -n "$search_csv" ]]; then
        echo "      nameservers:"
        if [[ -n "$dns_csv" ]]; then
          dns_yaml="$(echo "$dns_csv" | sed 's/[[:space:]]//g')"
          echo "        addresses: [${dns_yaml}]"
        fi
        if [[ -n "$search_csv" ]]; then
          search_yaml="$(echo "$search_csv" | sed 's/[[:space:]]//g')"
          echo "        search: [${search_yaml}]"
        fi
      fi
    } > "$tmp_file"

    if as_root test -f "$netplan_file"; then
      backup="${netplan_file}.bak.$(date +%Y%m%d-%H%M%S)"
      as_root cp -a "$netplan_file" "$backup"
      echo "Backed up existing netplan override to: $backup"
    fi

    as_root install -m 600 "$tmp_file" "$netplan_file"
    rm -f "$tmp_file"
    echo "Wrote netplan config: $netplan_file"

    as_root netplan generate
    echo "netplan generate: OK"

    if ask_yes_no "Apply netplan now? (Warning: may interrupt SSH connectivity)" "N"; then
      as_root netplan apply
      echo "netplan applied."
    else
      echo "Skipped netplan apply. Run later: sudo netplan apply"
    fi
  fi
else
  echo "Skipping static IP configuration."
fi

echo

# ---------- caddyfile update ----------

if [[ -n "$new_hostname" ]]; then
  if ask_yes_no "Hostname was changed. Update Caddyfile domain to match it?" "N"; then
    detected_caddyfile=""
    for p in "./caddy/conf/Caddyfile" "$HOME/caddy/conf/Caddyfile" "./Caddyfile" "/etc/caddy/Caddyfile"; do
      if [[ -f "$p" ]]; then
        detected_caddyfile="$p"
        break
      fi
    done

    caddyfile_path="$(ask_with_default "Path to Caddyfile" "${detected_caddyfile:-/etc/caddy/Caddyfile}")"

    if [[ ! -f "$caddyfile_path" ]]; then
      echo "Caddyfile not found at: $caddyfile_path"
      echo "Skipping Caddyfile update."
    else
      base_domain="$(ask_with_default "Base domain (example: example.com)" "example.com")"
      new_fqdn="${new_hostname}.${base_domain}"

      guessed_old="$(detect_first_site_label_from_caddyfile "$caddyfile_path" || true)"
      old_fqdn="$(ask_with_default "Current hostname/FQDN in Caddyfile to replace" "${guessed_old:-}")"

      if [[ -z "$old_fqdn" ]]; then
        echo "No old FQDN provided; skipping Caddyfile update."
      else
        backup="${caddyfile_path}.bak.$(date +%Y%m%d-%H%M%S)"
        as_root cp -a "$caddyfile_path" "$backup"
        echo "Backed up Caddyfile to: $backup"

        if command -v perl >/dev/null 2>&1; then
          as_root perl -i -pe "s/\Q$old_fqdn\E/$new_fqdn/g" "$caddyfile_path"
          echo "Updated Caddyfile: replaced '$old_fqdn' -> '$new_fqdn'"
        else
          echo "perl not found; cannot safely replace arbitrary hostname text."
          echo "Please edit manually: $caddyfile_path"
        fi

        if ask_yes_no "Reload/restart Caddy service now?" "N"; then
          if command -v systemctl >/dev/null 2>&1; then
            as_root systemctl reload caddy || as_root systemctl restart caddy
            echo "Caddy reloaded/restarted."
          else
            echo "systemctl not found; please restart Caddy manually."
          fi
        fi
      fi
    fi
  fi
fi

echo
echo "=== Reminder checklist ==="
cat <<'EOF'
Please review these post-init items:

1) Secrets hygiene
   - Confirm new login/LUKS/SSH credentials are recorded securely.
   - Remove or lock down any temporary plaintext secrets once no longer needed.

2) Service configuration
   - Verify Garage config, peers, and ports are correct for this site/environment.
   - Review Caddy routes/TLS/domain settings and external DNS records.

3) Network validation
   - Confirm hostname, IP, gateway, DNS, and reachability from management network.
   - If static IP was configured but not applied, run: sudo netplan apply

4) Access and security
   - Confirm SSH access policy and authorized_keys are as intended.
   - Verify firewall rules and VPN/tunnel settings (if used).

5) Runtime checks
   - Start/verify containers and inspect logs.
   - Confirm persistence volumes/mounts and disk expansion status.

6) Boot/unlock path
   - Validate initramfs + LUKS/Clevis/Tang behavior on reboot.
EOF

echo
echo "Finalisation complete."
