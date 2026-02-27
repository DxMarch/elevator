#!/usr/bin/env bash
# Syncs project files to remote elevator hosts via rsync over sshpass.
#
# Usage:
#   ./scripts/sync.sh --all          # sync to every host in scripts/hosts
#   ./scripts/sync.sh 24 20          # sync to specific elevator IDs
#
# Config:
#   scripts/.env   — SSHPASS and SYNC_DEST (secrets, gitignored)
#   scripts/get_hosts.sh  — host resolver for --all / selected IDs
#
# Only syncs: lib/, server/, config/, mix.exs, mix.lock, .env, scripts/{start,install}.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Config ────────────────────────────────────────────────────────────

ENV_FILE="scripts/.env"
GET_HOSTS_SCRIPT="scripts/get_hosts.sh"

[[ ! -f "$ENV_FILE" ]] && { echo "Missing $ENV_FILE. Copy scripts/.env.example and fill it in." >&2; exit 1; }
[[ ! -x "$GET_HOSTS_SCRIPT" ]] && { echo "Missing or non-executable $GET_HOSTS_SCRIPT" >&2; exit 1; }

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 --all | <id> [<id> ...]" >&2
  exit 1
fi

# ── Load secrets ──────────────────────────────────────────────────────

set -o allexport
source "$ENV_FILE"
set +o allexport

# ── Validate prerequisites ────────────────────────────────────────────

if ! command -v sshpass >/dev/null 2>&1; then
  echo "Missing dependency: sshpass (apt-get install -y sshpass)" >&2
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "Missing dependency: rsync (apt-get install -y rsync)" >&2
  exit 1
fi

: "${SSHPASS:?SSHPASS is not set in $ENV_FILE}"
: "${SYNC_DEST:?SYNC_DEST is not set in $ENV_FILE}"

# ── Resolve target hosts ──────────────────────────────────────────────

mapfile -t selected_hosts < <("$GET_HOSTS_SCRIPT" "$@")
[[ "${#selected_hosts[@]}" -eq 0 ]] && { echo "No hosts selected." >&2; exit 1; }

# ── Rsync command (whitelist-only via include/exclude) ────────────────

SSH_OPTS="sshpass -e ssh -o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new"

RSYNC=(
  rsync -avz
  --include='/lib/***'
  --include='/config/***'
  --include='/server/***'
  --include='/scripts/'
  --include='/scripts/start.sh'
  --include='/scripts/install.sh'
  --include='/mix.exs'
  --include='/mix.lock'
  --include='/.env'
  --exclude='*'
)

# ── Sync loop ─────────────────────────────────────────────────────────

failed_hosts=()

for host_line in "${selected_hosts[@]}"; do
  read -r id remote <<< "$host_line"

  echo "=== syncing elevator ${id} -> ${remote} ==="

  # Ensure the remote destination directory exists
  if ! SSHPASS="$SSHPASS" $SSH_OPTS "$remote" "mkdir -p '$SYNC_DEST'"; then
    echo "Failed to prepare destination on ${remote} (id ${id})" >&2
    failed_hosts+=("${id}:${remote}")
    continue
  fi

  if ! SSHPASS="$SSHPASS" RSYNC_RSH="$SSH_OPTS" \
    "${RSYNC[@]}" ./ "${remote}:${SYNC_DEST}/"; then
    echo "Rsync failed for ${remote} (id ${id})" >&2
    failed_hosts+=("${id}:${remote}")
    continue
  fi

  # Persist ELEVATOR_ID in .bashrc so start.sh can pick it up automatically
  SSHPASS="$SSHPASS" $SSH_OPTS "$remote" \
    "grep -q '^export ELEVATOR_ID=' ~/.bashrc 2>/dev/null \
      && sed -i 's/^export ELEVATOR_ID=.*/export ELEVATOR_ID=${id}/' ~/.bashrc \
      || echo 'export ELEVATOR_ID=${id}' >> ~/.bashrc"
done

# ── Summary ───────────────────────────────────────────────────────────

if [[ "${#failed_hosts[@]}" -gt 0 ]]; then
  echo "" >&2
  echo "Hosts that failed to sync:" >&2
  printf '  %s\n' "${failed_hosts[@]}" >&2
  exit 1
fi
