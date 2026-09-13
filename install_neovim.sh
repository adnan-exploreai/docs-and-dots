#!/usr/bin/env bash
set -euo pipefail

# install_neovim.sh - install Neovim + the NvChad distribution
#
# NvChad is lightweight (lazy-loaded plugins, fast startup), trivial to get
# started (clone + first run), and ships Catppuccin as a built-in theme -
# a good fit for a headless server.
#
# Usage:
#   ./install_neovim.sh            interactive
#   ./install_neovim.sh --yes      no prompts
#   TARGET_USER=alice ./install_neovim.sh --yes   (when run as root for another user)

LOG_FILE="${LOG_FILE:-$HOME/install_neovim.log}"

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

# --- 1. Neovim + prerequisites ----------------------------------------------
if confirm "Neovim (apt) + git/curl prerequisites"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y neovim git curl
  log "Neovim installed: $(nvim --version | head -n1)"
fi

# --- 2. NvChad distribution --------------------------------------------------
if confirm "NvChad distribution (cloned to ~/.config/nvim)"; then
  NVIM_DIR="$USER_HOME/.config/nvim"
  if [ -d "$NVIM_DIR" ] && [ -n "$(ls -A "$NVIM_DIR" 2>/dev/null || true)" ]; then
    warn "$NVIM_DIR already exists and is not empty - leaving it untouched."
  else
    git clone --depth 1 https://github.com/NvChad/NvChad "$NVIM_DIR"
    if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
      chown -R "$USER_NAME":"$USER_NAME" "$NVIM_DIR"
    fi
    log "NvChad cloned to $NVIM_DIR"
  fi
fi

# --- summary -----------------------------------------------------------------
echo
info "Next steps:"
echo "  - Run 'nvim' once - it will auto-install all NvChad plugins on first launch."
echo "  - Switch themes with ':NvChad theme' (Catppuccin is built in)."
echo "  - For proper icons, set your terminal font to a Nerd Font"
echo "    (e.g. JetBrainsMono Nerd Font) on the client side."
echo "  - Log: $LOG_FILE"
