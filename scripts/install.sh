#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/packages.list" >&2
  exit 1
fi

packages_file="$1"

if [[ ! -f "$packages_file" ]]; then
  echo "Error: file not found: $packages_file" >&2
  exit 1
fi

if [[ ! -r "$packages_file" ]]; then
  echo "Error: file is not readable: $packages_file" >&2
  exit 1
fi

packages=()

while IFS= read -r line || [[ -n "$line" ]]; do
  # Trim leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"

  # Skip empty lines and comment lines
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  packages+=("$line")
done < "$packages_file"

if [[ ${#packages[@]} -eq 0 ]]; then
  echo "No packages to install."
  exit 0
fi

apt install "${packages[@]}" -y

