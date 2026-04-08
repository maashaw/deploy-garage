#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/output/garage.toml /path/to/output/docker-compose.yml /path/to/secrets-dir /path/to/bootstrap-peers.txt [garage-template-path] [docker-compose-template-path]" >&2
  exit 1
}

[[ $# -ge 4 && $# -le 6 ]] || usage

output_toml="$1"
output_compose="$2"
secrets_dir="$3"
peers_file="$4"
garage_template="${5:-./garage.toml}"
compose_template="${6:-./docker-compose.template.yml}"

[[ -r "$garage_template" ]] || { echo "Error: garage template not readable: $garage_template" >&2; exit 1; }
[[ -r "$compose_template" ]] || { echo "Error: docker-compose template not readable: $compose_template" >&2; exit 1; }
[[ -r "$peers_file" ]] || { echo "Error: peers file not readable: $peers_file" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "Error: openssl is required." >&2; exit 1; }

if ! grep -q 'BOOTSTRAP_PEERS_REPLACE' "$garage_template"; then
  echo "Error: garage template does not contain BOOTSTRAP_PEERS_REPLACE token." >&2
  exit 1
fi

mkdir -p "$(dirname "$output_toml")"
mkdir -p "$(dirname "$output_compose")"

if [[ ! -d "$secrets_dir" ]]; then
  mkdir -p "$secrets_dir"
  chmod 700 "$secrets_dir"
fi

home_dir="${HOME:-}"
[[ -n "$home_dir" ]] || { echo "Error: HOME is empty; cannot personalise docker-compose bind paths." >&2; exit 1; }

# Correct formats per your requirement
rpc_secret="$(openssl rand -hex 32 | tr -d '\n')"
metrics_token="$(openssl rand -base64 32 | tr -d '\n')"
admin_token="$(openssl rand -base64 32 | tr -d '\n')"

umask 077
printf '%s' "$rpc_secret"    > "$secrets_dir/rpc_secret.txt"
printf '%s' "$metrics_token" > "$secrets_dir/metrics_token.txt"
printf '%s' "$admin_token"   > "$secrets_dir/admin_token.txt"

# Determine indentation level from the BOOTSTRAP_PEERS_REPLACE line
indent="$(awk '/BOOTSTRAP_PEERS_REPLACE/ { match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH); exit }' "$garage_template")"

# Read peers, trim whitespace, skip empty lines
peers=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  peers+=("$line")
done < "$peers_file"

# Build formatted peers block:
#   <indent>"node1",
#   <indent>"node2"
formatted_peers=""
count="${#peers[@]}"
if (( count > 0 )); then
  for i in "${!peers[@]}"; do
    comma=""
    if (( i < count - 1 )); then
      comma=","
    fi
    formatted_peers+="${indent}\"${peers[$i]}\"${comma}"
    if (( i < count - 1 )); then
      formatted_peers+=$'\n'
    fi
  done
fi

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'
}

escape_sed_replacement_slash() {
  printf '%s' "$1" | sed -e 's/[\/&|\\]/\\&/g'
}

rpc_secret_esc="$(escape_sed_replacement "$rpc_secret")"
metrics_token_esc="$(escape_sed_replacement "$metrics_token")"
admin_token_esc="$(escape_sed_replacement "$admin_token")"
home_dir_esc="$(escape_sed_replacement_slash "$home_dir")"

tmp1="$(mktemp)"
tmp2="$(mktemp)"
tmp3="$(mktemp)"
trap 'rm -f "$tmp1" "$tmp2" "$tmp3"' EXIT

# Replace BOOTSTRAP_PEERS_REPLACE with the generated multiline peers block
awk -v repl="$formatted_peers" '
  /BOOTSTRAP_PEERS_REPLACE/ {
    if (length(repl) > 0) print repl
    next
  }
  { print }
' "$garage_template" > "$tmp1"

# Replace secrets in garage.toml
sed \
  -e "s|RPC_SECRET_REPLACE|$rpc_secret_esc|g" \
  -e "s|METRICS_TOKEN_REPLACE|$metrics_token_esc|g" \
  -e "s|ADMIN_TOKEN_REPLACE|$admin_token_esc|g" \
  "$tmp1" > "$tmp2"

mv "$tmp2" "$output_toml"
chmod 600 "$output_toml"

# Personalise docker-compose bind paths:
# 1) tokenized template (__HOME_DIR__)
# 2) legacy hardcoded path (/home/michael)
sed \
  -e "s|__HOME_DIR__|$home_dir_esc|g" \
  "$compose_template" > "$tmp3"

mv "$tmp3" "$output_compose"
chmod 600 "$output_compose"

echo "Done."
echo "Garage config written to: $output_toml"
echo "Docker compose written to: $output_compose"
echo "Secrets written to: $secrets_dir"
echo "Bootstrap peers loaded from: $peers_file"
echo "Home directory used for bind paths: $home_dir"
