#!/usr/bin/env bash
set -euo pipefail

# setup_debian.sh - bootstrap a fresh Debian 12 install
#
# Installs:
#   0. Sudo user creation       (fresh server with only root; + SSH public key)
#   1. Core system packages   (zsh, git, curl, jq, tmux, build tools, ...)
#   2. Search tools           (ripgrep, fzf, fd, bat, zoxide, tldr)
#   3. Modern replacements    (eza, duf from GitHub releases)
#   4. Shell setup            (zsh default, Starship + Catppuccin, zsh plugins)
#   5. AI tooling             (herdr, opencode)
#   6. Containers             (Docker Engine + Compose plugin, official repo)
#   7. Dev toolchains         (rustup, Python + uv, Neovim+NvChad, Node.js 20 LTS)
#   8. Monitoring             (btop, ncdu, unattended-upgrades)
#   9. Security               (ufw firewall, fail2ban)
#  10. Misc CLI               (yq, sqlite3)
#
# Usage:
#   ./setup_debian.sh           interactive - confirms each section
#   ./setup_debian.sh --yes     install everything without prompting

LOG_FILE="${LOG_FILE:-$HOME/setup_debian.log}"

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
  # $1 = description; returns 0 to install, 1 to skip
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

# Run a command as the target user (matters when script is run as root).
run_as_user() {
  if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
    su -s /bin/bash "$USER_NAME" -c "$*"
  else
    bash -c "$*"
  fi
}

# Download the latest release binary of a GitHub project to /usr/local/bin.
#   install_github_release <owner/repo> <asset grep pattern> <binary name>
install_github_release() {
  local repo="$1" pattern="$2" name="$3"
  local url tmp bin
  log "Installing $name from GitHub releases..."
  url="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
    | jq -r '.assets[].browser_download_url' | grep -E "$pattern" | head -n1 || true)"
  [ -n "$url" ] || die "Could not find a release asset for $name"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/$name.tar.gz"
  tar -xzf "$tmp/$name.tar.gz" -C "$tmp"
  bin="$(find "$tmp" -maxdepth 3 -type f -name "$name" | head -n1)"
  [ -n "$bin" ] || die "Binary '$name' not found inside the release archive"
  install -m 0755 "$bin" "/usr/local/bin/$name"
  rm -rf "$tmp"
  log "$name installed."
}

# ---------------------------------------------------------------------------
# Environment / privilege detection
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
  USER_NAME="${SUDO_USER:-root}"
  USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
  [ -n "$USER_HOME" ] || USER_HOME="/root"
else
  SUDO="sudo"
  USER_NAME="$(id -un)"
  USER_HOME="$HOME"
  command -v sudo >/dev/null 2>&1 || die "sudo not found and you are not root."
fi

# ---------------------------------------------------------------------------
# 0. User setup (create a sudo user, or reuse an existing one)
# ---------------------------------------------------------------------------
# Only offered when we are logged in as root and this is not a sudo session.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ] && confirm "Create (or reuse) a sudo user for daily use"; then
  NEW_USER=""
  while [ -z "$NEW_USER" ]; do
    read -rp "  Username: " NEW_USER
  done

  if id "$NEW_USER" >/dev/null 2>&1; then
    warn "User '$NEW_USER' already exists - using it for the rest of the setup."
    if ! groups "$NEW_USER" | tr ' ' '\n' | grep -qx sudo; then
      usermod -aG sudo "$NEW_USER"
      log "Added '$NEW_USER' to the sudo group."
    fi
  else
    # Debian convention: a user's primary group has the same name
    groupadd -f "$NEW_USER"
    useradd -m -g "$NEW_USER" -s "$(command -v bash)" -G sudo "$NEW_USER"
    log "User '$NEW_USER' created (primary group '$NEW_USER', added to sudo)."

    if [ -t 0 ]; then
      info "Set a password for '$NEW_USER':"
      passwd "$NEW_USER"
    else
      NEW_PASS="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16 || true)"
      echo "$NEW_USER:$NEW_PASS" | chpasswd
      warn "Password for '$NEW_USER' set to: $NEW_PASS  (change it after first login)"
    fi
  fi

  USER_NAME="$NEW_USER"
  USER_HOME="$(getent passwd "$NEW_USER" | cut -d: -f6)"

  # Install the user's public key so SSH login works
  SSH_KEY_SOURCE="${SSH_KEY_SOURCE:-}"
  if [ -z "$SSH_KEY_SOURCE" ]; then
    for candidate in \
      "/root/.ssh/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub" \
      "/root/.ssh/id_rsa.pub" "$HOME/.ssh/id_rsa.pub" \
      "/root/.ssh/id_ecdsa.pub" "$HOME/.ssh/id_ecdsa.pub" \
      /home/*/.ssh/id_ed25519.pub /home/*/.ssh/id_rsa.pub; do
      [ -f "$candidate" ] && SSH_KEY_SOURCE="$candidate" && break
    done
  fi
  if [ -n "$SSH_KEY_SOURCE" ] && [ -f "$SSH_KEY_SOURCE" ]; then
    USER_GID="$(id -gn "$NEW_USER")"
    install -d -m 700 -o "$NEW_USER" -g "$USER_GID" "$USER_HOME/.ssh"
    touch "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown "$NEW_USER":"$USER_GID" "$USER_HOME/.ssh/authorized_keys"
    if grep -Fqx "$(head -n1 "$SSH_KEY_SOURCE")" "$USER_HOME/.ssh/authorized_keys"; then
      info "Public key already present in $USER_HOME/.ssh/authorized_keys."
    else
      cat "$SSH_KEY_SOURCE" >> "$USER_HOME/.ssh/authorized_keys"
      log "Added public key from $SSH_KEY_SOURCE to $USER_HOME/.ssh/authorized_keys."
    fi
  else
    warn "No SSH public key found on this server (looked in /root/.ssh and $HOME/.ssh) - skipping SSH key setup."
  fi

  log "The rest of the script will configure everything for '$USER_NAME'."
fi

export USER_NAME USER_HOME

info "Target user: $USER_NAME (home: $USER_HOME)"
info "Log: $LOG_FILE"

# ---------------------------------------------------------------------------
# 1. Core system packages + search tools (apt)
# ---------------------------------------------------------------------------
if confirm "Core packages (zsh, git, curl, jq, tmux, ripgrep, fzf, bat, zoxide, ...)"; then
  info "Updating package lists (may take a while)..."
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
    zsh git curl wget jq unzip ca-certificates build-essential \
    tmux htop tree ripgrep fzf fd-find bat tldr zoxide
  log "Core packages installed."

  # Debian ships bat/fd under different names
  command -v bat >/dev/null 2>&1 || $SUDO ln -sf "$(command -v batcat)" /usr/local/bin/bat
  command -v fd  >/dev/null 2>&1 || $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd

  # zoxide fallback for very old mirrors
  if ! command -v zoxide >/dev/null 2>&1; then
    warn "zoxide missing from apt - installing from GitHub..."
    install_github_release "ajeetdsouza/zoxide" "x86_64-unknown-linux-musl\.tar\.gz" "zoxide"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Modern replacements (GitHub release binaries)
# ---------------------------------------------------------------------------
if confirm "Modern CLI tools (eza, duf)"; then
  install_github_release "eza-community/eza" "x86_64-unknown-linux-gnu\.tar\.gz" "eza"
  install_github_release "muesli/duf" "linux_x86_64\.tar\.gz" "duf"
fi

# ---------------------------------------------------------------------------
# 3. Shell setup: zsh as default, Starship + Catppuccin, zsh plugins
# ---------------------------------------------------------------------------
if confirm "Shell setup (zsh default, Starship + Catppuccin theme, zsh plugins)"; then
  command -v zsh >/dev/null 2>&1 || die "zsh is not installed (run the core packages step first)."

  # zsh plugins (autosuggestions + syntax highlighting)
  if [ ! -d "$USER_HOME/.zsh/zsh-autosuggestions" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$USER_HOME/.zsh/zsh-autosuggestions"
  fi
  if [ ! -d "$USER_HOME/.zsh/zsh-syntax-highlighting" ]; then
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$USER_HOME/.zsh/zsh-syntax-highlighting"
  fi
  log "zsh plugins cloned."

  # Starship prompt + Catppuccin theme
  if ! command -v starship >/dev/null 2>&1; then
    info "Installing Starship prompt..."
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y
  fi
  mkdir -p "$USER_HOME/.config"
  curl -fsSL https://raw.githubusercontent.com/catppuccin/starship/main/themes/mocha.toml \
    -o "$USER_HOME/.config/starship.toml"
  log "Starship configured with Catppuccin Mocha."

  # .zshrc (backup any existing file first)
  if [ -f "$USER_HOME/.zshrc" ] && [ ! -f "$USER_HOME/.zshrc.bak" ]; then
    cp "$USER_HOME/.zshrc" "$USER_HOME/.zshrc.bak"
    warn "Existing .zshrc backed up to ~/.zshrc.bak"
  fi
  cat > "$USER_HOME/.zshrc" <<'EOF'
# --- generated by setup_debian.sh ---
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# aliases
alias ls='eza --group-directories-first --git'
alias la='eza --group-directories-first --git -la'
alias lt='eza --group-directories-first --git --tree --level=2'
alias lrt='eza -lr -s modified' 
alias cat='bat'

# bat theme
export BAT_THEME="Catppuccin Mocha"

# fzf - modern versions expose --zsh, older Debian uses the example files
if fzf --zsh >/dev/null 2>&1; then
  source <(fzf --zsh)
elif [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
  source /usr/share/doc/fzf/examples/key-bindings.zsh
  [ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
fi
export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

# zoxide
eval "$(zoxide init zsh)"

# zsh plugins
[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# starship prompt
eval "$(starship init zsh)"
EOF
  log ".zshrc written."

  # make zsh the default shell
  ZSH_BIN="$(command -v zsh)"
  if [ "$(id -u)" -eq 0 ]; then
    usermod -s "$ZSH_BIN" "$USER_NAME"
  else
    $SUDO usermod -s "$ZSH_BIN" "$USER_NAME"
  fi
  log "Default shell set to $ZSH_BIN for $USER_NAME."

  # fix ownership when running as root
  if [ "$(id -u)" -eq 0 ] && [ "$USER_NAME" != "root" ]; then
    chown -R "$USER_NAME":"$USER_NAME" "$USER_HOME/.zshrc" "$USER_HOME/.zsh" "$USER_HOME/.config" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# 4. Git identity (only when interactive)
# ---------------------------------------------------------------------------
if [ -t 0 ] && [ ! -f "$USER_HOME/.gitconfig" ] && confirm "Set your git user.name / user.email"; then
  read -rp "  git user.name:  " git_name
  read -rp "  git user.email: " git_email
  run_as_user "git config --global user.name '$git_name' && git config --global user.email '$git_email'"
  log "Git identity configured."
fi

# ---------------------------------------------------------------------------
# 5. AI tooling
# ---------------------------------------------------------------------------
if confirm "AI tooling (herdr - agent terminal runtime, opencode - AI coding agent)"; then
  info "Installing herdr (https://herdr.dev)..."
  run_as_user 'curl -fsSL https://herdr.dev/install.sh | sh'
  log "herdr installed."

  info "Installing opencode (https://opencode.ai)..."
  run_as_user 'curl -LsSf https://opencode.ai/install | bash'
  log "opencode installed."
fi

# ---------------------------------------------------------------------------
# 6. Containers: Docker Engine + Compose plugin (official Docker repo)
# ---------------------------------------------------------------------------
if confirm "Containers (Docker Engine + Compose plugin from Docker's official repo)"; then
  info "Adding Docker's official apt repository..."
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
  DOCKER_ARCH="$(dpkg --print-architecture)"
  DOCKER_CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$DOCKER_ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $DOCKER_CODENAME stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

  DEBIAN_FRONTEND=noninteractive $SUDO apt-get update
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
    gnupg docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log "Docker Engine + Compose plugin installed."

  $SUDO usermod -aG docker "$USER_NAME"
  log "Added '$USER_NAME' to the 'docker' group (effective after re-login)."
fi

# ---------------------------------------------------------------------------
# 7. Dev toolchains: rustup, Python + uv, neovim, Node.js LTS
# ---------------------------------------------------------------------------
if confirm "Dev toolchains (rustup, Python + uv, neovim, Node.js 20 LTS + npm)"; then
  # Rust toolchain (user-level, installs to ~/.cargo)
  if ! command -v cargo >/dev/null 2>&1; then
    info "Installing Rust via rustup..."
    run_as_user 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default'
  fi

  # Python: system python + uv (fast package manager, manages its own pythons)
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y python3 python3-pip python3-venv
  if ! command -v uv >/dev/null 2>&1; then
    info "Installing uv..."
    run_as_user 'curl -LsSf https://astral.sh/uv/install.sh | sh'
  fi

  # Neovim + NvChad distribution via the dedicated installer
  if [ -f "$(dirname "$0")/install_neovim.sh" ]; then
    TARGET_USER="$USER_NAME" "$(dirname "$0")/install_neovim.sh" --yes
  else
    warn "install_neovim.sh not found next to this script - installing plain neovim via apt."
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y neovim
  fi

  # Node.js 20 LTS + npm from NodeSource
  if ! command -v node >/dev/null 2>&1; then
    info "Adding NodeSource repo and installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | $SUDO bash -
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y nodejs
  fi
  log "Dev toolchains installed."

  # make cargo/uv available in the target user's zsh
  if [ -f "$USER_HOME/.zshrc" ] && ! grep -q "cargo/env" "$USER_HOME/.zshrc"; then
    cat >> "$USER_HOME/.zshrc" <<'EOF'

# --- dev toolchains (added by setup_debian.sh) ---
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
EOF
    log "Added cargo to ~/.zshrc."
  fi
fi

# ---------------------------------------------------------------------------
# 8. Monitoring + automatic security updates
# ---------------------------------------------------------------------------
if confirm "Monitoring + auto-updates (btop, ncdu, unattended-upgrades)"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y btop ncdu unattended-upgrades
  echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
  echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
  log "btop, ncdu installed; unattended security upgrades enabled."
fi

# ---------------------------------------------------------------------------
# 9. Security: ufw firewall + fail2ban
# ---------------------------------------------------------------------------
if confirm "Security (ufw firewall + fail2ban brute-force protection)"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y ufw fail2ban

  # allow SSH BEFORE enabling the firewall so we never lock ourselves out
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing
  $SUDO ufw allow OpenSSH
  $SUDO ufw --force enable
  log "ufw enabled (SSH allowed, everything else denied)."

  $SUDO systemctl enable --now fail2ban
  log "fail2ban enabled."
fi

# ---------------------------------------------------------------------------
# 10. Misc CLI: yq (YAML), sqlite3
# ---------------------------------------------------------------------------
if confirm "Misc CLI (yq for YAML, sqlite3)"; then
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y sqlite3
  if ! command -v yq >/dev/null 2>&1; then
    install_github_release "mikefarah/yq" "yq_linux_amd64\.tar\.gz" "yq"
  fi
  log "yq and sqlite3 installed."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
log "All done! Log written to $LOG_FILE"
echo
info "Next steps:"
echo "  - Open a new shell (or: exec zsh) to load zsh + Starship."
echo "  - Run 'starship preset --help' if you want a different Catppuccin flavour (latte/frappe/macchiato)."
echo "  - herdr:   run 'herdr' to start the agent terminal runtime (ctrl+b q detaches, 'herdr' reattaches)."
echo "  - opencode: run 'opencode' to start the AI coding agent."
echo "  - eza/duf/bat/zoxide/fzf are wired up via aliases and init hooks in ~/.zshrc."
echo "  - Docker: 'docker compose version' to verify; log out/in for the docker group to apply."
echo "  - Toolchains: 'node -v', 'cargo --version', 'uv --version' to verify (cargo needs a new shell)."
echo "  - ufw: 'ufw status' to check the firewall (SSH was allowed before enabling)."
if [ -n "${NEW_USER:-}" ]; then
  echo "  - Log out of root and log in as '$NEW_USER'; consider disabling SSH root login afterwards."
fi
