#!/bin/bash
# Remove all private keys (and their .pub companions) from ~/.ssh

set -euo pipefail

ssh_dir="${1:-$HOME/.ssh}"

if [[ ! -d "$ssh_dir" ]]; then
  echo "No $ssh_dir directory found; nothing to do."
  exit 0
fi

removed=0
for f in "$ssh_dir"/*; do
  [[ -f "$f" ]] || continue
  [[ "$f" != *.pub ]] || continue

  first_line="$(head -n 1 "$f" 2>/dev/null)" || continue
  if [[ "$first_line" =~ ^-----BEGIN\ .*PRIVATE\ KEY----- ]]; then
    echo "Removing: $f"
    rm -f "$f" "${f}.pub"
    removed=$((removed + 1))
  fi
done

echo "Removed $removed private key(s) from $ssh_dir."
