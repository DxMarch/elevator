#!/usr/bin/env bash
set -euo pipefail

# Setup script: syncs the elevator project to remote hosts and runs remote_setup.sh
# on each to install Elixir and configure .env files.
# Expects username "student" and hosts on the 10.100.23.0/24 subnet.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v rsync >/dev/null 2>&1; then
	echo "rsync not found; please install rsync (e.g. sudo apt install rsync) and re-run." >&2
	exit 1
fi

# Get host IPs from NODES in .env file
HOSTS=$("$SCRIPT_DIR/get_hosts.sh" | tr '\n' ' ')
if [ -z "$HOSTS" ]; then
	echo "No hosts found" >&2
	exit 0
fi
echo "Connecting to hosts: $HOSTS"

# SSH options: batch mode, connection reuse via ControlMaster
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=6 -o ControlMaster=auto -o ControlPersist=60s -o ControlPath=$HOME/.ssh/cm-%r@%h:%p -o LogLevel=ERROR"

# Ensure local control-socket directory exists for ControlPath
mkdir -p "$HOME/.ssh" || true

for host in $HOSTS; do
	echo "--> Processing host: $host"

	RSYNC_SRC="$PROJECT_ROOT/"
	RSYNC_DEST="/home/student/gruppe23/elevator"

	# Ensure parent directory exists on remote
	ssh $SSH_OPTS student@"$host" 'mkdir -p /home/student/gruppe23' >/dev/null 2>&1 || true

	echo "Syncing project with rsync"
	if ! rsync -az --delete --exclude='.git' -e "ssh $SSH_OPTS" "$RSYNC_SRC" "student@${host}:$RSYNC_DEST"; then
		echo "rsync failed for $host -- skipping remote setup." >&2
		continue
	fi

	# Run remote_setup.sh on the remote host to install Elixir and update .env
	echo "Running remote setup script"
	if ! ssh $SSH_OPTS student@"$host" "bash -lc '$RSYNC_DEST/scripts/remote_setup.sh'"; then
		echo "Remote setup failed for $host" >&2
		continue  # Continue with other hosts instead of exiting
	fi

	echo "--> Completed host: $host"
done

echo "All hosts processed."
