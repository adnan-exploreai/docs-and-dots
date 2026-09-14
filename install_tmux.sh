#!/usr/bin/env bash
set -euo pipefail

# install_tmux.sh - install tmux, deploy the Catppuccin tmux config, and
# install the TPM plugins (tmux-sensible, catppuccin/tmux).
#
# The config and plugins live in ~/.config/tmux/ (XDG), including tpm itself,
# so the 'run' line in tmux.conf points there.
#
# Usage:
#   ./install_tmux.sh            interactive
#   ./install_tmux.sh --yes      no prompts
#   TARGET_USER=alice ./install_tmux.sh --yes   (when run as root for another user)

LOG_FILE="${LOG_FILE:-$HOME/install_tmux.log}"

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

own_target_dir() {
  # When running as root for another user, make sure the target's config is
  # owned by them, not root (root-owned dirs break tpm's writability check).
  if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
    chown -R "$USER_NAME":"$USER_NAME" "$1"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMUX_CONF_SRC="$SCRIPT_DIR/tmux.conf"
CONF_DIR="$USER_HOME/.config/tmux"
PLUGINS_DIR="$CONF_DIR/plugins"

info "Target user: $USER_NAME (home: $USER_HOME)"

# --- 1. tmux + git ------------------------------------------------------------
if confirm "tmux package (apt)"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y tmux git
  log "tmux installed: $(tmux -V)"
fi

# --- 2. deploy tmux.conf ------------------------------------------------------
if confirm "Catppuccin tmux config (~/.config/tmux/tmux.conf)"; then
  [ -f "$TMUX_CONF_SRC" ] || die "tmux.conf not found next to this script: $TMUX_CONF_SRC"
  mkdir -p "$CONF_DIR"
  own_target_dir "$CONF_DIR"
  if [ -f "$CONF_DIR/tmux.conf" ] && [ ! -f "$CONF_DIR/tmux.conf.bak" ]; then
    cp "$CONF_DIR/tmux.conf" "$CONF_DIR/tmux.conf.bak"
    warn "Existing tmux.conf backed up to ~/.config/tmux/tmux.conf.bak"
  fi
  cp "$TMUX_CONF_SRC" "$CONF_DIR/tmux.conf"
  log "tmux.conf deployed."
fi

# --- 3. TPM plugins -----------------------------------------------------------
if confirm "TPM plugins (tpm, tmux-sensible, catppuccin/tmux)"; then
  mkdir -p "$PLUGINS_DIR"
  # chown BEFORE tpm runs: tpm checks writability as the target user and will
  # fail (and `set -e` would skip the chown below) if dirs are root-owned.
  own_target_dir "$PLUGINS_DIR"

  clone_plugin() {
    local name="$1" url="$2"
    if [ -d "$PLUGINS_DIR/$name" ]; then
      info "Plugin '$name' already present - skipping clone."
    else
      git clone --depth 1 "$url" "$PLUGINS_DIR/$name"
    fi
  }

  clone_plugin "tpm"            "https://github.com/tmux-plugins/tpm"
  clone_plugin "tmux-sensible"  "https://github.com/tmux-plugins/tmux-sensible"
  clone_plugin "tmux"           "https://github.com/catppuccin/tmux"
  log "TPM plugins cloned."

  # let tpm resolve/install anything missing from the @plugin list
  if [ -x "$PLUGINS_DIR/tpm/bin/install_plugins" ]; then
    run_as_user "'$PLUGINS_DIR/tpm/bin/install_plugins'" \
      || warn "TPM install_plugins reported a problem - re-run it as $USER_NAME after this script."
    log "TPM plugin install run completed."
  fi

  # final sweep: fix ownership even if tpm or a clone failed above
  own_target_dir "$CONF_DIR"
fi

# --- summary ------------------------------------------------------------------
echo
info "Next steps:"
echo "  - Start a session with 'tmux' - the Catppuccin theme and keybindings are active."
echo "  - Prefix is C-Space; Alt+H / Alt+L switch windows; mouse is on."
echo "  - To add plugins later, edit ~/.config/tmux/tmux.conf and run:"
echo "      tmux source-file ~/.config/tmux/tmux.conf && ~/.config/tmux/plugins/tpm/bin/install_plugins"
echo "  - Log: $LOG_FILE"
