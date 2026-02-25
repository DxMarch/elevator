#!/usr/bin/env bash
set -euo pipefail

# Distribute your public SSH key to all hosts listed in envs/.env (10.100.23.*).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $0 [--password PASSWORD] [path-to-pubkey]

  --password, -p  Provide the remote password on the command line (not recommended).
                  Preferred: export SSHPASS in your environment before running.
  path-to-pubkey   Optional path to the public key (defaults to ~/.ssh/id_ed25519.pub)
EOF
}

# Parse options (simple)
PASSWORD="${SSHPASS:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--password)
      shift
      if [ $# -eq 0 ]; then
        echo "Error: --password requires an argument" >&2
        usage
        exit 1
      fi
      PASSWORD="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # positional: path to pubkey
      KEY_PATH="$1"
      shift
      ;;
  esac
done

# Determine key path if not provided
if [ -z "${KEY_PATH:-}" ]; then
  if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    KEY_PATH="$HOME/.ssh/id_ed25519.pub"
  elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    KEY_PATH="$HOME/.ssh/id_rsa.pub"
  else
    echo "No public key found (looked at defaults)" >&2
    echo "Generate one with: ssh-keygen -t ed25519 -C 'your-email'" >&2
    exit 1
  fi
fi

# If still no password in environment or via flag, prompt the user for action
if [ -z "${PASSWORD:-}" ]; then
  echo "SSHPASS is not set in your environment. Recommended: export SSHPASS=your_password before running."
  read -r -p "Do you want to enter the password now (will be used only for this run)? [y/N] " yn
  case "$yn" in
    [Yy]* )
      read -s -r -p "Password: " PASSWORD
      echo
      ;;
    * )
      echo "Aborting. Set SSHPASS or provide --password to continue." >&2
      exit 1
      ;;
  esac
fi

HOSTS=$("$SCRIPT_DIR/get_hosts.sh" | tr '\n' ' ')
if [ -z "$HOSTS" ]; then
  echo "No hosts found"
  exit 0
fi

SSH_OPTS='-o StrictHostKeyChecking=accept-new -o ConnectTimeout=6 -o LogLevel=ERROR'

echo "Using public key: $KEY_PATH"
echo "Targets: $HOSTS"

any_failed=0
for host in $HOSTS; do
  echo "Adding key to $host"
  if command -v ssh-copy-id >/dev/null 2>&1; then
    if [ -n "${PASSWORD:-}" ] && command -v sshpass >/dev/null 2>&1; then
      out=$(sshpass -p "$PASSWORD" ssh-copy-id -i "$KEY_PATH" $SSH_OPTS student@"$host" 2>&1) || rc=$?
      rc=${rc:-$?}
    else
      out=$(ssh-copy-id -i "$KEY_PATH" $SSH_OPTS student@"$host" 2>&1) || rc=$?
      rc=${rc:-$?}
    fi
    if [ ${rc:-0} -ne 0 ]; then
      echo "  ERROR: ssh-copy-id failed for $host (exit: ${rc:-})" >&2
      echo "  Output: $out" >&2
      any_failed=1
    else
      if printf "%s" "$out" | grep -q "All keys were skipped"; then
        echo "  Already installed on $host"
      elif printf "%s" "$out" | grep -q "Number of key(s) added"; then
        echo "  Key added on $host"
      else
        echo "  ssh-copy-id succeeded for $host"
      fi
    fi
  else
    # Fallback: append key using ssh (with sshpass if available)
    if [ -n "${PASSWORD:-}" ] && command -v sshpass >/dev/null 2>&1; then
      out=$(sshpass -p "$PASSWORD" ssh $SSH_OPTS student@"$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$KEY_PATH" 2>&1) || rc=$?
      rc=${rc:-$?}
    else
      out=$(ssh $SSH_OPTS student@"$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" < "$KEY_PATH" 2>&1) || rc=$?
      rc=${rc:-$?}
    fi
    if [ ${rc:-0} -ne 0 ]; then
      echo "  ERROR: ssh append failed for $host (exit: ${rc:-})" >&2
      echo "  Output: $out" >&2
      any_failed=1
    else
      echo "  Key appended on $host"
    fi
  fi
done

if [ "$any_failed" -ne 0 ]; then
  echo "Some hosts failed to receive the key" >&2
  exit 1
fi

echo "Done. Test with: ssh student@<host>"
