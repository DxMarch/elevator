#!/usr/bin/env bash
# Usage:
#   ./scripts/install.sh
#
# Runs on the current machine:
# - Ensures Elixir >= 1.19 is installed (installs if missing/old)
# - Adds Elixir/OTP bins to ~/.bashrc
# - Runs mix local.hex/local.rebar and mix deps.get

set -euo pipefail

cd "$(dirname "$0")/.."

ELIXIR_VERSION="${ELIXIR_VERSION:-1.19.5}"
OTP_VERSION="${OTP_VERSION:-28.1}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.elixir-install/installs}"
OTP_MAJOR="${OTP_VERSION%%.*}"
ELIXIR_BIN_DIR="$INSTALL_ROOT/elixir/${ELIXIR_VERSION}-otp-${OTP_MAJOR}/bin"
OTP_BIN_DIR="$INSTALL_ROOT/otp/${OTP_VERSION}/bin"

elixir_ok() {
  local version_line

  if ! command -v elixir >/dev/null 2>&1; then
    return 1
  fi

  version_line="$(elixir --version 2>/dev/null | awk '/^Elixir / {print; exit}')"
  [[ -z "$version_line" ]] && return 1

  echo "$version_line" | awk '{split($2, v, "."); exit (v[1] > 1 || (v[1] == 1 && v[2] >= 19)) ? 0 : 1}'
}

ensure_bashrc_path() {
  local bashrc="$HOME/.bashrc"
  touch "$bashrc"

  if ! grep -Fq "$ELIXIR_BIN_DIR" "$bashrc" 2>/dev/null; then
    {
      echo ""
      echo "# Elixir toolchain (added by scripts/install.sh)"
      echo "export PATH=\"$OTP_BIN_DIR:\$PATH\""
      echo "export PATH=\"$ELIXIR_BIN_DIR:\$PATH\""
    } >> "$bashrc"
  fi

  export PATH="$OTP_BIN_DIR:$PATH"
  export PATH="$ELIXIR_BIN_DIR:$PATH"
}

if ! elixir_ok; then
  echo "Installing Elixir ${ELIXIR_VERSION} (OTP ${OTP_VERSION}) ..."
  curl -fsSL -o /tmp/elixir-install.sh https://elixir-lang.org/install.sh
  sh /tmp/elixir-install.sh "elixir@${ELIXIR_VERSION}" "otp@${OTP_VERSION}"
  rm -f /tmp/elixir-install.sh
fi

ensure_bashrc_path

if ! elixir_ok; then
  echo "Elixir >= 1.19 was not detected after install." >&2
  exit 1
fi

echo "Using $(elixir --version | awk '/^Elixir / {print; exit}')"

mix local.hex --force
mix local.rebar --force
mix deps.get
