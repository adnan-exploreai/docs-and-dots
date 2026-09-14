#!/usr/bin/env bash
set -euo pipefail

# install_pi.sh - install the pi coding agent (https://pi.dev) on a server
#
# pi is a minimal terminal coding harness. It requires Node.js >= 22.19.0 and
# npm (the distro packages on Debian 12 ship Node 18, too old). This script:
#
#   1. Installs prerequisites       (git, curl, ca-certificates)
#   2. Ensures Node.js >= 22.19.0   (NodeSource latest LTS when needed)
#   3. Installs pi                  (official installer, https://pi.dev/install.sh)
#
# pi is installed for the target user via npm, so it lands in a user-writable
# prefix (~/.local/bin when the global prefix is not writable) and `pi update`
# keeps working for that user.
#
# Usage:
#   ./install_pi.sh            interactive
#   ./install_pi.sh --yes      no prompts
#   TARGET_USER=alice ./install_pi.sh --yes   (when run as root for another user)

LOG_FILE="${LOG_FILE:-$HOME/install_pi.log}"

c_ok='\033[0;32m'; c_info='\033[0;34m'; c_warn='\033[0;33m'; c_err='\033[0;31m'; c_off='\033[0m'
log()  { printf "${c_ok}[ok]${c_off}  %s\n" "$*" | tee -a "$LOG_FILE"; }
info() { printf "${c_info}[..]${c_off}  %s\n" "$*" | tee -a "$LOG_FILE"; }
warn() { printf "${c_warn}[!!]${c_off}  %s\n" "$*" | tee -a "$LOG_FILE"; }
die()  { printf "${c_err}[!!]${c_off}  %s\n" "$*" >&2; exit 1; }

AUTO="no"
for arg in "$@"; do
  case "$arg" in
    -y|--yes|--assume-yes) AUTO="yes" ;;
  esac
done

confirm() {
  if [ "$AUTO" = "yes" ]; then
    log "Installing: $1"
    return 0
  fi
  printf "${c_info}?${c_off} %s [Y/n] " "$1"
  read -r answer
  case "$answer" in
    ""|Y|y|yes|Yes|YES) return 0 ;;
    *) info "Skipping: $1"; return 1 ;;
  esac
}

run_as_user() {
  if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
    su -s /bin/bash "$USER_NAME" -c "$*"
  else
    bash -c "$*"
  fi
}

# --- target user ------------------------------------------------------------
if [ -n "${TARGET_USER:-}" ]; then
  USER_NAME="$TARGET_USER"
  USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  [ -n "$USER_HOME" ] || die "User '$USER_NAME' does not exist."
else
  if [ "$(id -u)" -eq 0 ]; then
    USER_NAME="${SUDO_USER:-root}"
    USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
    [ -n "$USER_HOME" ] || USER_HOME="/root"
  else
    USER_NAME="$(id -un)"
    USER_HOME="$HOME"
  fi
fi
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

info "Target user: $USER_NAME (home: $USER_HOME)"
info "Log: $LOG_FILE"

# --- version helper ----------------------------------------------------------
# pi needs Node.js >= 22.19.0. Returns 0 if the installed node satisfies it.
node_version_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local v major minor patch
  v="$(node --version 2>/dev/null)"; v="${v#v}"
  IFS=. read -r major minor patch <<< "$v"
  [ "${major:-0}" -gt 22 ] && return 0
  [ "${major:-0}" -eq 22 ] && [ "${minor:-0}" -ge 19 ] && return 0
  return 1
}

# --- 1. prerequisites ----------------------------------------------------------
if confirm "Prerequisites (git, curl, ca-certificates)"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git curl ca-certificates
  log "Prerequisites installed."
fi

# --- 2. Node.js >= 22.19.0 (NodeSource latest LTS when missing/too old) --------
if confirm "Node.js >= 22.19.0 (required by pi, installed via NodeSource if missing)"; then
  if node_version_ok && command -v npm >/dev/null 2>&1; then
    log "Node.js $(node --version) with npm already present - skipping."
  else
    info "Installing the latest Node.js LTS + npm from NodeSource..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO bash -
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y nodejs
    if node_version_ok && command -v npm >/dev/null 2>&1; then
      log "Node.js $(node --version) + npm installed."
    else
      die "Node.js >= 22.19.0 / npm is still missing after installation."
    fi
  fi
fi

# --- 3. pi ---------------------------------------------------------------------
install_pi_official() {
  if [ "$AUTO" = "yes" ]; then
    # The official installer shows a confirmation menu read from /dev/tty.
    # setsid drops the controlling terminal, so the installer takes its
    # documented non-interactive path ("continuing without confirmation").
    run_as_user "setsid sh -c 'curl -fsSL https://pi.dev/install.sh | sh' < /dev/null"
  else
    run_as_user 'curl -fsSL https://pi.dev/install.sh | sh'
  fi
}

PI_BIN="$(command -v pi 2>/dev/null || true)"
if [ -n "$PI_BIN" ]; then
  if confirm "pi - already installed at $PI_BIN, reinstall with the official installer"; then
    info "Reinstalling pi..."
    install_pi_official
  else
    info "Skipping: pi already installed ($PI_BIN)."
  fi
elif confirm "pi coding agent (official installer)"; then
  info "Installing pi (https://pi.dev) for $USER_NAME..."
  install_pi_official
fi

# --- verify + PATH -------------------------------------------------------------
PI_BIN="$(command -v pi 2>/dev/null || true)"
if [ -z "$PI_BIN" ]; then
  PI_BIN="$(run_as_user 'command -v pi 2>/dev/null || true')"
fi
if [ -z "$PI_BIN" ]; then
  for candidate in "$USER_HOME/.local/bin/pi" /usr/local/bin/pi /usr/bin/pi; do
    if [ -x "$candidate" ]; then PI_BIN="$candidate"; break; fi
  done
fi

if [ -n "$PI_BIN" ]; then
  log "pi installed at: $PI_BIN"
  PI_BIN_DIR="$(dirname "$PI_BIN")"
  if [ "$PI_BIN_DIR" = "$USER_HOME/.local/bin" ]; then
    if [ -f "$USER_HOME/.zshrc" ] && ! grep -q '\.local/bin' "$USER_HOME/.zshrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$USER_HOME/.zshrc"
      if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
        chown "$USER_NAME":"$USER_NAME" "$USER_HOME/.zshrc"
      fi
      log "Added ~/.local/bin to PATH in ~/.zshrc"
    fi
  fi
else
  warn "Could not locate the pi binary after installation."
fi

# --- summary -------------------------------------------------------------------
echo
info "Next steps:"
echo "  - Run 'pi' to launch the coding agent, then '/login' to authenticate with a provider"
echo "    (or export an API key first, e.g. ANTHROPIC_API_KEY=sk-ant-...)."
echo "  - Switch providers/models with /model once logged in (Ctrl+L opens the picker)."
echo "  - Update pi later with: pi update"
if [ -n "$PI_BIN" ] && ! echo ":$PATH:" | grep -q ":$(dirname "$PI_BIN"):"; then
  echo "  - If 'pi' is not found in new shells, add its bin dir to your shell profile:"
  echo "      export PATH=\"$(dirname "$PI_BIN"):\$PATH\""
fi
echo "  - Log: $LOG_FILE"