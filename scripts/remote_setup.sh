#!/usr/bin/env bash
set -euo pipefail

# Remote setup script: installs Elixir if necessary and updates .env
# This script runs ON the remote host (no SSH calls inside).

# Installation paths and versions
installs_dir="$HOME/.elixir-install/installs"
elixir_bin="$installs_dir/elixir/1.19.5-otp-28/bin"
otp_bin="$installs_dir/otp/28.1/bin"
project_path="$HOME/gruppe23/elevator"

# Check for Elixir >=1.19 and return version line if found
get_local_elixir_version() {
	local ver_line
	
	# Helper to extract the 'Elixir' line from elixir --version output
	extract_elixir_line() {
		awk '/^Elixir[[:space:]]/ { print; exit }'
	}

	# First try: use elixir in current PATH (picks up exports from this script)
	ver_line=$(elixir --version 2>/dev/null | extract_elixir_line || true)

	# If not found, try explicit installed bin path
	if [ -z "${ver_line:-}" ] && [ -x "${elixir_bin}/elixir" ]; then
		ver_line=$("${elixir_bin}/elixir" --version 2>/dev/null | extract_elixir_line || true)
	fi

	# Return early if no version found
	if [ -z "${ver_line:-}" ]; then
		return 1
	fi

	# Parse and check version (require >=1.19)
	if [[ "${ver_line}" =~ Elixir[[:space:]]([0-9]+)\.([0-9]+) ]]; then
		local maj=${BASH_REMATCH[1]}
		local min=${BASH_REMATCH[2]}
		if [ "$maj" -gt 1 ] || { [ "$maj" -eq 1 ] && [ "$min" -ge 19 ]; }; then
			printf '%s' "$ver_line"
			return 0
		else
			echo "Elixir version too old: ${maj}.${min} (need >=1.19)" >&2
			return 1
		fi
	else
		echo "Could not parse Elixir version from: ${ver_line}" >&2
		return 1
	fi
}

# Add PATH exports to ~/.bashrc if not already present
BASHRC="$HOME/.bashrc"
touch "$BASHRC"  # Ensure file exists
if ! grep -Fq "$elixir_bin" "$BASHRC" 2>/dev/null; then
	echo "" >> "$BASHRC"
	echo "# Elixir PATH exports (added by remote_setup.sh)" >> "$BASHRC"
	echo "export PATH=\"$elixir_bin:\$PATH\"" >> "$BASHRC"
	echo "export PATH=\"$otp_bin:\$PATH\"" >> "$BASHRC"
	echo "PATH exports added to $BASHRC"
	
	# Source the updated .bashrc in current shell so PATH takes effect immediately
	export PATH="$elixir_bin:$otp_bin:$PATH"
else
	echo "PATH exports already present in $BASHRC"
fi

echo "Checking for Elixir on remote host..."
if ver=$(get_local_elixir_version); then
	echo "Elixir present: $ver (skipping installation)"
else
	echo "Elixir >=1.19 not found, installing..."	
	# Download and run the official Elixir installer (idempotent - won't reinstall if present)
	if curl -fsSL -o /tmp/install_elixir.sh https://elixir-lang.org/install.sh; then
		sh /tmp/install_elixir.sh elixir@1.19.5 otp@28.1 || echo "Warning: elixir installer exited with error" >&2
		rm -f /tmp/install_elixir.sh || true
	else
		echo "Warning: failed to download Elixir installer" >&2
	fi

	# After installation, update PATH in current shell immediately
	export PATH="$elixir_bin:$otp_bin:$PATH"

	# Verify installation succeeded (now with updated PATH)
	if ver=$(get_local_elixir_version); then
		echo "Elixir installed successfully: $ver"
	else
		echo "Warning: Failed to locate Elixir after installation attempt" >&2
	fi
fi

# Update .env: swap LOCAL_NODE with the node matching this host's IP
echo "Updating .env file..."
ENV_FILE="$project_path/envs/.env"
if [ ! -f "$ENV_FILE" ]; then
	echo ".env file not found at $ENV_FILE, skipping env update" >&2
	exit 0
fi

# Get this host's IP address
HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
	echo "Could not determine host IP, skipping env update" >&2
	exit 0
fi

# Extract current LOCAL_NODE value
CURRENT_LOCAL_NODE=$(grep -m1 "^LOCAL_NODE=" "$ENV_FILE" 2>/dev/null | sed 's/^LOCAL_NODE="//;s/"$//' || true)

# Extract all node entries from the NODES variable (handles multiline quoted values)
ALL_NODES=$(awk '/^NODES=/ {
	sub(/^NODES="/, "")
	line = $0
	while (line !~ /"$/) {
		if (getline > 0) {
			line = line "\n" $0
		} else break
	}
	sub(/"$/, "", line)
	print line
}' "$ENV_FILE")

# Find the node matching this host's IP in NODES
NEW_LOCAL_NODE=$(printf "%s\n" "$ALL_NODES" | grep -E "^[^@]+@${HOST_IP}$" | head -n1 || true)

if [ -z "$NEW_LOCAL_NODE" ]; then
	echo "No node found for IP $HOST_IP in NODES, skipping env update" >&2
	exit 0
fi

# Check if LOCAL_NODE is already correct
if [ "$CURRENT_LOCAL_NODE" = "$NEW_LOCAL_NODE" ]; then
	echo "LOCAL_NODE already set to $NEW_LOCAL_NODE (no changes needed)"
	exit 0
fi

echo "Updating LOCAL_NODE from '$CURRENT_LOCAL_NODE' to '$NEW_LOCAL_NODE'"

# Build new NODES list: remove NEW_LOCAL_NODE and add back CURRENT_LOCAL_NODE
NEW_NODES=$(printf "%s\n" "$ALL_NODES" | grep -v -x -- "${NEW_LOCAL_NODE}" || true)
if [ -n "$CURRENT_LOCAL_NODE" ]; then
	if [ -n "$NEW_NODES" ]; then
		NEW_NODES="${CURRENT_LOCAL_NODE}
${NEW_NODES}"
	else
		NEW_NODES="$CURRENT_LOCAL_NODE"
	fi
fi

# Update the .env file in-place
awk -v new_local="$NEW_LOCAL_NODE" -v new_nodes="$NEW_NODES" '
	/^LOCAL_NODE=/ {
		print "LOCAL_NODE=\"" new_local "\""
		next
	}
	/^NODES=/ {
		print "NODES=\"" new_nodes "\""
		# Skip original NODES lines until closing quote
		while (getline > 0 && $0 !~ /"$/) {}
		next
	}
	{print}
' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"

echo "Successfully updated LOCAL_NODE to: $NEW_LOCAL_NODE"

