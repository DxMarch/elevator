#!/usr/bin/env bash
# Resolves elevator hosts from scripts/hosts.
#
# Usage:
#   ./scripts/get_hosts.sh --all
#   ./scripts/get_hosts.sh 24 26
#
# Output format (stdout):
#   <id> <user@host>

set -euo pipefail
cd "$(dirname "$0")/.."

HOSTS_FILE="scripts/hosts"
[[ ! -f "$HOSTS_FILE" ]] && { echo "Missing $HOSTS_FILE" >&2; exit 1; }

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 --all | <id> [<id> ...]" >&2
  exit 1
fi

declare -A host_map=()
host_order=()

while read -r id host _rest; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  host_map["$id"]="$host"
  host_order+=("$id")
done < "$HOSTS_FILE"

[[ "${#host_order[@]}" -eq 0 ]] && { echo "No hosts found in $HOSTS_FILE" >&2; exit 1; }

selected_ids=()
if [[ "$1" == "--all" ]]; then
  selected_ids=("${host_order[@]}")
else
  read -r -a selected_ids <<< "$*"
  [[ "${#selected_ids[@]}" -eq 0 ]] && { echo "No elevator IDs provided." >&2; exit 1; }
fi

for id in "${selected_ids[@]}"; do
  remote="${host_map[$id]:-}"
  if [[ -z "$remote" ]]; then
    echo "No host configured for elevator id ${id}" >&2
    exit 1
  fi
  printf '%s %s\n' "$id" "$remote"
done