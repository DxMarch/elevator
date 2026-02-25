#!/usr/bin/env bash
set -euo pipefail

# Outputs host information by parsing the NODES variable from envs/.env
# Default behavior: prints one host IP per line (for SSH connections)
# Option:
#   -n|--nodes   print full node@ip entries (one per line)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/envs/.env"

# Parse command-line option
mode="ip_only"
if [ "${1-}" = "-n" ] || [ "${1-}" = "--nodes" ]; then
  mode="nodes"
fi

if [ ! -f "$ENV_FILE" ]; then
  echo ".env file not found at $ENV_FILE" >&2
  exit 1
fi

# Extract NODES value using Perl to handle quoted multiline values
# Matches: NODES="node1@ip\nnode2@ip" or NODES=single_value
nodes=$(perl -0777 -ne '
  if (/^NODES\s*=\s*"(.*?)"/ms) { print $1 }
  elsif (/^NODES\s*=\s*([^\n\r"]\S*)/m) { print $1 }
' "$ENV_FILE" || true)

# Normalize line endings (handle Windows CRLF if present)
nodes=$(echo "$nodes" | tr '\r' '\n')

# Exit early if no nodes found
if [ -z "$nodes" ]; then
  echo "No NODES found in $ENV_FILE" >&2
  exit 0
fi

if [ "$mode" = "nodes" ]; then
  # Output full node@ip entries (one per line)
  echo "$nodes" | sed '/^\s*$/d' | sort -u
else
  # Default: output only IP addresses (strip node@ prefix)
  echo "$nodes" | sed '/^\s*$/d' | sed 's/.*@//' | sort -u
fi
