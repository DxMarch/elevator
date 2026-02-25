#!/usr/bin/env bash
set -euo pipefail

# Starts a tmux session with one pane per host

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

HOSTS=($("$PROJECT_ROOT/scripts/get_hosts.sh" -n))
if [ ${#HOSTS[@]} -eq 0 ]; then
	echo "No hosts found"
	exit 0
fi

echo "Opening tmux session with shells on: ${HOSTS[*]}"

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=6 -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=$HOME/.ssh/cm-%r@%h:%p -o LogLevel=ERROR"

# Ensure local control-socket directory exists for ControlPath
mkdir -p "$HOME/.ssh" || true

# Simple session name
SESSION_NAME="elevator"

# Kill existing session if it exists (avoid tmux printing 'no sessions')
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
	tmux kill-session -t "$SESSION_NAME"
fi

# Create new tmux session with a local shell in the first pane
tmux new-session -d -s "$SESSION_NAME"

# Set tmux options to display pane titles in borders (ignore errors on old tmux versions)
tmux set-option -t "$SESSION_NAME" pane-border-format "#{pane_index}: #{pane_title}" 2>/dev/null || true
tmux set-option -t "$SESSION_NAME" pane-active-border-format "#{pane_index}: #{pane_title}" 2>/dev/null || true

# Add a pane for each host with SSH shells
for host in "${HOSTS[@]}"; do
	# Split node@ip into separate variables
	node="${host%@*}"
	ip="${host#*@}"
	
	# Create split pane with SSH to the IP, capture pane ID for title setting
	pane_id=$(tmux split-window -t "${SESSION_NAME}:" -h -P -F "#{pane_id}" \
		"ssh $SSH_OPTS -t student@${ip} 'exec bash -l'")
	
	# Set pane title to show node@ip for easy identification
	tmux select-pane -t "$pane_id" -T "${node}@${ip}"
	
	# Arrange panes in tiled layout
	tmux select-layout -t "${SESSION_NAME}:" tiled
done

# Attach to the session
tmux attach-session -t "${SESSION_NAME}:"