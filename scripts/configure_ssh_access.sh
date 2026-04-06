#!/bin/bash
#
# Disables password and keyboard-interactive authentication in sshd,
# forcing public-key authentication for all SSH access.

set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP="${SSHD_CONFIG}.$(date +%Y%m%d%H%M%S).old"

# ---------- preflight checks ----------

if [[ ! -f "$SSHD_CONFIG" ]]; then
    echo "ERROR: ${SSHD_CONFIG} not found." >&2
    exit 1
fi

# ---------- helper function ----------

# apply_setting KEY VALUE
#   If the key exists (commented or not), replace the first occurrence.
#   If it does not exist at all, append it.
apply_setting() {
    local key="$1"
    local value="$2"

    # Match lines that are either active or commented-out instances of the key.
    # The regex handles optional leading whitespace/#, and any current value.
    if grep -qEi "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]" "$SSHD_CONFIG"; then
        # Replace the first occurrence (whether commented out or not) with the
        # desired value.  Subsequent duplicate lines, if any, are left alone;
        # sshd uses the first match, which will now be correct.
        sed -i "0,/^[[:space:]]*#\?[[:space:]]*${key}[[:space:]].*/s//${key} ${value}/" "$SSHD_CONFIG"
        echo "  Updated existing entry: ${key} ${value}"
    else
        # Append the directive at the end of the file.
        printf '\n%s %s\n' "$key" "$value" >> "$SSHD_CONFIG"
        echo "  Appended new entry:     ${key} ${value}"
    fi
}

# ---------- main ----------

echo "Backing up ${SSHD_CONFIG} to ${BACKUP}"
cp -p "$SSHD_CONFIG" "$BACKUP"

echo "Applying sshd hardening settings..."
apply_setting "PasswordAuthentication"       "no"
apply_setting "KbdInteractiveAuthentication" "no"

# Older OpenSSH versions use ChallengeResponseAuthentication instead of
# KbdInteractiveAuthentication.  Handle it if present so that legacy
# systems are also covered.
if grep -qEi "^[[:space:]]*#?[[:space:]]*ChallengeResponseAuthentication[[:space:]]" "$SSHD_CONFIG"; then
    apply_setting "ChallengeResponseAuthentication" "no"
fi

# ---------- validate and reload ----------

echo "Validating sshd configuration..."
if sshd -t -f "$SSHD_CONFIG"; then
    echo "Configuration valid."
else
    echo "ERROR: sshd configuration test failed. Restoring backup." >&2
    cp -p "$BACKUP" "$SSHD_CONFIG"
    exit 1
fi

echo "Restarting sshd..."
if systemctl is-active --quiet sshd 2>/dev/null; then
    systemctl restart sshd
elif systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl restart ssh
else
    # Fallback for non-systemd or differently-named service
    echo "WARNING: Could not detect sshd service name. Attempting SIGHUP on running daemon." >&2
    pkill -HUP sshd || true
fi

echo "Done. Password and keyboard-interactive authentication are now disabled."
