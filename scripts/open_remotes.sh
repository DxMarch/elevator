#!/usr/bin/env bash
# Opens a tmux session with one pane per remote elevator host.
# Each pane SSHs into the host and starts a tmux session there.
#
# Usage:
#   ./scripts/open_remotes.sh --all
#   ./scripts/open_remotes.sh 24 26

set -euo pipefail
cd "$(dirname "$0")/.."

# ── Config ────────────────────────────────────────────────────────────

ENV_FILE="scripts/.env"
GET_HOSTS_SCRIPT="scripts/get_hosts.sh"
SESSION_NAME="elevator"

[[ ! -f "$ENV_FILE" ]] && { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ ! -x "$GET_HOSTS_SCRIPT" ]] && { echo "Missing or non-executable $GET_HOSTS_SCRIPT" >&2; exit 1; }

if [[ "$#" -lt 1 ]]; then
  echo "Usage: $0 --all | <id> [<id> ...]" >&2
  exit 1
fi

set -o allexport
source "$ENV_FILE"
set +o allexport

# ── Resolve selected hosts ────────────────────────────────────────────

mapfile -t selected_hosts < <("$GET_HOSTS_SCRIPT" "$@")
if [[ "${#selected_hosts[@]}" -eq 0 ]]; then
  echo "No hosts selected." >&2
  exit 1
fi

# ── Prerequisites ─────────────────────────────────────────────────────

for cmd in tmux sshpass; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

: "${SSHPASS:?SSHPASS is not set in $ENV_FILE}"
: "${SYNC_DEST:?SYNC_DEST is not set in $ENV_FILE}"

SSH_OPTS="-o ConnectTimeout=6 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR"

# ── Build tmux session ────────────────────────────────────────────────

# If the local session exists, recreate it from scratch.
# Remote sessions persist because each SSH pane runs `tmux new-session -A` remotely.
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  tmux kill-session -t "$SESSION_NAME"
fi

first=true
selected_ids=()
for host_line in "${selected_hosts[@]}"; do
  read -r id remote <<< "$host_line"
  selected_ids+=("$id")

  # SSH command that attaches (or creates) a tmux session on the remote, starting in the project dir
  ssh_cmd="sshpass -e ssh $SSH_OPTS -t $remote 'tmux new-session -A -s elevator -c $SYNC_DEST'"

  if $first; then
    # First host creates the local tmux session
    tmux new-session -d -s "$SESSION_NAME" -x "$(tput cols)" -y "$(tput lines)" \
      -e "SSHPASS=$SSHPASS" "$ssh_cmd"
    first=false
  else
    tmux split-window -t "${SESSION_NAME}:" -h \
      -e "SSHPASS=$SSHPASS" "$ssh_cmd"
    tmux select-layout -t "${SESSION_NAME}:" tiled
  fi

  # Label the pane with the elevator ID and host
  tmux select-pane -T "elevator ${id} (${remote})"
done

# Show pane titles in the borders
tmux set-option -t "$SESSION_NAME" pane-border-format " #{pane_index}: #{pane_title} " 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-border-status top 2>/dev/null || true

# ── Attach ────────────────────────────────────────────────────────────

echo "Connecting to: ${selected_ids[*]}"
exec tmux attach-session -t "$SESSION_NAME"
