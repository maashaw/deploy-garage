#!/bin/bash
# Add a serial port to the grub options

set -euo pipefail

grub_file="/etc/default/grub"

set_grub_key() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "$grub_file"; then
    sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$grub_file"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$grub_file"
  fi
}

echo 'Setting up Serial Port...'
set_grub_key "GRUB_CMDLINE_LINUX_DEFAULT" "console=tty0 console=ttyS0,115200n8"
set_grub_key "GRUB_CMDLINE_LINUX" "console serial"
set_grub_key "GRUB_SERIAL_COMMAND" "serial --unit=0 speed=115200 word=8 --parity=no --stop=1"

echo 'Updating Bootloader...'
update-grub
