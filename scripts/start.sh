#!/usr/bin/env bash
# Usage:
#   ./scripts/start.sh              # cluster mode, uses ELEVATOR_ID from env
#   ./scripts/start.sh <id>         # cluster mode, explicit ID
#   ./scripts/start.sh --local <id> # localhost dev mode
#   ./scripts/start.sh --port 15658 # override simulator driver port
#
# The elevator ID is resolved from the CLI argument or the ELEVATOR_ID
# env var (written to .bashrc on remotes by sync.sh).
#
# Reads ERLANG_COOKIE and GOSSIP_SECRET from .env (or the environment).

set -euo pipefail

LOCAL=false
ID=""
PORT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL=true
      shift
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo "Error: --port requires a value" >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    --port=*)
      PORT="${1#*=}"
      shift
      ;;
    --*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "$ID" ]]; then
        echo "Error: multiple IDs provided ($ID, $1)" >&2
        exit 1
      fi
      ID="$1"
      shift
      ;;
  esac
done

if [[ -n "$PORT" && ! "$PORT" =~ ^[0-9]+$ ]]; then
  echo "Error: --port must be an integer" >&2
  exit 1
fi

# Local mode always needs an explicit ID (multiple nodes share one machine)
if [[ "$LOCAL" == true && ( -z "$ID" || ! "$ID" =~ ^[0-9]+$ ) ]]; then
  echo "Usage: $0 --local <id>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -o allexport
  source .env
  set +o allexport
fi

# ── Resolve elevator ID ───────────────────────────────────────────────
# Priority: CLI argument > ELEVATOR_ID env var (set by sync.sh in .bashrc)

if [[ -z "$ID" && -n "${ELEVATOR_ID:-}" ]]; then
  ID="$ELEVATOR_ID"
fi

if [[ -z "$ID" || ! "$ID" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 <id>" >&2
  echo "Optional: --local and --port <number>" >&2
  echo "Or set ELEVATOR_ID in the environment." >&2
  exit 1
fi

if [[ -n "$PORT" ]]; then
  export DRIVER_PORT="$PORT"
  echo "Using driver port: ${DRIVER_PORT}"
fi

# ── Start node ────────────────────────────────────────────────────────

if [[ "$LOCAL" == true ]]; then
  ERLANG_COOKIE="${ERLANG_COOKIE:-elevator_dev}"
  # Hardcoded secret keeps local nodes from accidentally joining a real cluster.
  export GOSSIP_SECRET="elevator_local_dev"
  echo "Starting elev${ID} (localhost) ..."
  exec iex --sname "elev${ID}" --cookie "$ERLANG_COOKIE" -S mix
else
  ERLANG_COOKIE="${ERLANG_COOKIE:?ERLANG_COOKIE is not set. Add it to .env}"
  LOCAL_IP="${LOCAL_IP:-$(hostname -I | awk '{print $1}')}"
  echo "Starting elev${ID}@${LOCAL_IP} (cluster) ..."
  exec iex --name "elev${ID}@${LOCAL_IP}" --cookie "$ERLANG_COOKIE" -S mix
fi
