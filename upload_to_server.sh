#!/usr/bin/env bash
set -euo pipefail

# upload_to_server.sh - upload the bootstrap files (SSH key + setup scripts)
# to a fresh Debian server, so you can run the provisioning there.
#
# Usage:
#   ./upload_to_server.sh root@<server-ip>
#   ./upload_to_server.sh -k ~/.ssh/id_ed25519.pub root@<server-ip> [-p 2222]
#
# Options:
#   -k, --key <path>   path to the SSH public key to upload
#                      (default: ~/.ssh/id_ed25519.pub)
#
# Uploads:
#   <public key>          -> /root/.ssh/id_ed25519.pub
#   setup_debian.sh       -> /root/setup_debian.sh
#   install_neovim.sh     -> /root/install_neovim.sh   (if present)
#   install_tmux.sh       -> /root/install_tmux.sh     (if present)
#   install_pi.sh         -> /root/install_pi.sh       (if present)
#   tmux.conf             -> /root/tmux.conf           (if present)
#
# You will be prompted for the server's root password.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

c_ok='\033[0;32m'; c_info='\033[0;34m'; c_warn='\033[0;33m'; c_err='\033[0;31m'; c_off='\033[0m'
log()  { printf "${c_ok}[ok]${c_off}  %s\n" "$*"; }
info() { printf "${c_info}[..]${c_off}  %s\n" "$*"; }
warn() { printf "${c_warn}[!!]${c_off}  %s\n" "$*"; }
die()  { printf "${c_err}[!!]${c_off}  %s\n" "$*" >&2; exit 1; }
step() { printf "\n${c_info}==>${c_off} %s\n" "$*"; }

# --- parse arguments ----------------------------------------------------------
KEY_PUB="${KEY_PUB:-$HOME/.ssh/id_ed25519.pub}"
HOST=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -k|--key)
      [ "$#" -ge 2 ] || die "$1 requires a path argument"
      KEY_PUB="$2"
      shift 2
      ;;
    -h|--help)
      die "usage: $0 [-k <pubkey_path>] <user@host> [ssh args...]"
      ;;
    -*)
      break
      ;;
    *)
      [ -z "$HOST" ] || die "unexpected extra argument: $1"
      HOST="$1"
      shift
      ;;
  esac
done

if [ -z "$HOST" ]; then
  die "usage: $0 [-k <pubkey_path>] <user@host> [ssh args...]"
fi

# --- validate local files ------------------------------------------------------
[ -f "$KEY_PUB" ] || die "Public key not found: $KEY_PUB"

SETUP_SCRIPT="$SCRIPT_DIR/setup_debian.sh"
[ -f "$SETUP_SCRIPT" ] || die "setup_debian.sh not found next to this script: $SETUP_SCRIPT"

NEOVIM_SCRIPT="$SCRIPT_DIR/install_neovim.sh"

info "Target:       $HOST"
info "SSH key:      $KEY_PUB"
info "Setup script: $SETUP_SCRIPT"

# --- upload the SSH public key -------------------------------------------------
step "Uploading SSH public key to $HOST:/root/.ssh/"
cat "$KEY_PUB" | ssh "$@" "$HOST" \
  "install -d -m 700 /root/.ssh && cat > /root/.ssh/id_ed25519.pub && chmod 600 /root/.ssh/id_ed25519.pub" \
  || die "Failed to upload the SSH public key."
log "SSH public key uploaded."

# --- upload setup_debian.sh ----------------------------------------------------
step "Uploading setup_debian.sh to $HOST:/root/"
scp "$@" "$SETUP_SCRIPT" "$HOST:/root/setup_debian.sh" \
  || die "Failed to upload setup_debian.sh."
log "setup_debian.sh uploaded."

# --- upload install_neovim.sh (optional) --------------------------------------
if [ -f "$NEOVIM_SCRIPT" ]; then
  step "Uploading install_neovim.sh to $HOST:/root/"
  scp "$@" "$NEOVIM_SCRIPT" "$HOST:/root/install_neovim.sh" \
    || die "Failed to upload install_neovim.sh."
  log "install_neovim.sh uploaded."
else
  warn "install_neovim.sh not found next to this script - skipping."
fi

# --- upload install_pi.sh (optional) -------------------------------------------
PI_SCRIPT="$SCRIPT_DIR/install_pi.sh"
if [ -f "$PI_SCRIPT" ]; then
  step "Uploading install_pi.sh to $HOST:/root/"
  scp "$@" "$PI_SCRIPT" "$HOST:/root/install_pi.sh" \
    || die "Failed to upload install_pi.sh."
  log "install_pi.sh uploaded."
else
  warn "install_pi.sh not found next to this script - skipping."
fi

# --- upload install_tmux.sh + tmux.conf (optional) ----------------------------
TMUX_SCRIPT="$SCRIPT_DIR/install_tmux.sh"
TMUX_CONF="$SCRIPT_DIR/tmux.conf"
if [ -f "$TMUX_SCRIPT" ] && [ -f "$TMUX_CONF" ]; then
  step "Uploading install_tmux.sh + tmux.conf to $HOST:/root/"
  scp "$@" "$TMUX_SCRIPT" "$HOST:/root/install_tmux.sh" \
    || die "Failed to upload install_tmux.sh."
  scp "$@" "$TMUX_CONF" "$HOST:/root/tmux.conf" \
    || die "Failed to upload tmux.conf."
  log "install_tmux.sh + tmux.conf uploaded."
else
  warn "install_tmux.sh / tmux.conf not found next to this script - skipping."
fi

# --- summary -------------------------------------------------------------------
echo
log "All files uploaded to $HOST."
echo "Next steps:"
echo "  1. SSH into the server:            ssh $HOST"
echo "  2. Run the bootstrap:              bash /root/setup_debian.sh"
echo "  3. It will find the uploaded key and add it to the new user's authorized_keys."
