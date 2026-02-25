#!/usr/bin/env bash
set -euo pipefail

# usage
usage() {
  cat <<EOF
Usage: $0 [--local] [--name NAME] [--help]

  --local        Run locally (no distributed node). If --name is provided
                 with --local, the node will be started on loopback as NAME@127.0.0.1
  --name NAME    Set the local node name (either full NAME@IP or just NAME)
  --help         Show this help
EOF
}


# parse args
LOCAL=false
MANUAL_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --local)
      LOCAL=true
      shift
      ;;
    --name)
      MANUAL_NAME="$2"
      shift 2
      ;;
    --name=*)
      MANUAL_NAME="${1#--name=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # ignore unknown args (or pass through in future)
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# load env file if present (works with simple KEY=VALUE .env)
if [ -f "$PROJECT_ROOT/envs/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/envs/.env"
  set +a
fi

COOKIE="${ELEVATOR_COOKIE:-changeme}"

# deterministic distribution port range (override with DIST_MIN/DIST_MAX env vars)
DIST_MIN="${DIST_MIN:-9100}"
DIST_MAX="${DIST_MAX:-9105}"
ERL_FLAGS="-kernel inet_dist_listen_min ${DIST_MIN} inet_dist_listen_max ${DIST_MAX}"

if [ "$LOCAL" = true ]; then
  if [ -n "$MANUAL_NAME" ]; then
    # if user supplied a full name (contains @) use it, otherwise use loopback ip
    if [[ "$MANUAL_NAME" == *@* ]]; then
      NODE_NAME="$MANUAL_NAME"
    else
      NODE_NAME="${MANUAL_NAME}@127.0.0.1"
    fi

  cd "$PROJECT_ROOT" && exec elixir --name "$NODE_NAME" --cookie "$COOKIE" -S mix run --no-halt
  else
    # local without distribution
  cd "$PROJECT_ROOT" && exec elixir -S mix run --no-halt
  fi
else
  # non-local (distributed)
  if [ -n "$MANUAL_NAME" ]; then
    # Always use the IP from LOCAL_NODE if available; replace any hostname part
    # of MANUAL_NAME and keep only the name portion before any '@'.
    if [[ "$MANUAL_NAME" == *@* ]]; then
      name_part="${MANUAL_NAME%@*}"
    else
      name_part="$MANUAL_NAME"
    fi

    if [ -n "${LOCAL_NODE:-}" ] && [[ "${LOCAL_NODE}" == *@* ]]; then
      ip="${LOCAL_NODE#*@}"
    else
      ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    fi

    NODE_NAME="${name_part}@${ip}"
  else
    NODE_NAME="${LOCAL_NODE:-elevator@$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1") }"
  fi

  cd "$PROJECT_ROOT" && exec elixir --name "$NODE_NAME" --cookie "$COOKIE" --erl "$ERL_FLAGS" -S mix run --no-halt
fi