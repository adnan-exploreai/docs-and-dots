# docs-and-dots

Bootstrap scripts for a fresh Debian 12 server: user setup, shell + tooling
with a Catppuccin theme, AI tooling, and Docker.

## Files

| File | Purpose |
| --- | --- |
| `upload_to_server.sh` | Upload your SSH public key and the setup scripts to a fresh server |
| `setup_debian.sh` | Main bootstrap: user, packages, shell, AI tooling, Docker, toolchains |
| `install_neovim.sh` | Standalone Neovim + NvChad installer (called by `setup_debian.sh`) |
| `install_tmux.sh` | Standalone tmux config + TPM plugins installer (called by `setup_debian.sh`) |
| `install_pi.sh` | Standalone pi coding agent installer, incl. Node.js >= 22.19 (called by `setup_debian.sh`) |
| `tmux.conf` | tmux config (Catppuccin Mocha, C-Space prefix, mouse) used by `install_tmux.sh` |

## Quick start

Run from your local machine against a fresh Debian 12 server that only has a
root account:

```bash
./upload_to_server.sh -k ~/.ssh/id_ed25519.pub root@<server-ip>
```

This uploads your public key and both setup scripts to the server. Then SSH in
and run:

```bash
ssh root@<server-ip>
bash /root/setup_debian.sh
```

`setup_debian.sh` walks through each section interactively; pass `--yes` to
install everything without prompts.

## What gets installed

1. **User setup** — create a sudo user (or reuse an existing one), set a
   password, add your SSH public key to `~/.ssh/authorized_keys`
2. **Core packages** — zsh, git, curl, jq, tmux, build-essential, ripgrep, fzf,
   fd, bat, zoxide, tldr, htop, tree
3. **Modern replacements** — eza, duf (GitHub release binaries)
4. **Shell setup** — zsh as default shell, Starship prompt with the Catppuccin
   Mocha theme, zsh-autosuggestions, zsh-syntax-highlighting
5. **AI tooling** — herdr (agent terminal runtime), opencode (AI coding agent), pi (coding harness)
6. **Containers** — Docker Engine + Compose plugin from Docker's official repo
7. **Dev toolchains** — rustup, Python + uv, Neovim + NvChad, Node.js latest LTS + npm
8. **Monitoring** — btop, ncdu, unattended security upgrades
9. **Security** — ufw firewall (SSH allowed, rest denied)
10. **Misc CLI** — yq, sqlite3
11. **tmux** — Catppuccin Mocha config (C-Space prefix, mouse, split-to-cwd) + TPM plugins (`tmux-sensible`, `catppuccin/tmux`)

## Notes

- **Root only in the beginning:** `setup_debian.sh` creates a sudo user for
  daily use; the rest of the script configures that account.
- **SSH key lookup:** `setup_debian.sh` auto-detects a public key among
  `id_ed25519.pub`, `id_rsa.pub`, and `id_ecdsa.pub` in `/root/.ssh` or
  `$HOME/.ssh`. Override with `SSH_KEY_SOURCE=/path/to/key.pub`.
- **Docker group:** the target user is added to `docker`; log out/in for it to
  take effect.
- **Node.js latest LTS:** pi requires Node.js >= 22.19.0, which Debian 12's
  packages don't satisfy. `install_pi.sh` installs the latest Node.js LTS from
  NodeSource (via the `setup_lts.x` alias) when needed, and `setup_debian.sh`
  adds it if `node` is missing or too old.
- **pi:** first run `pi`, then `/login` to authenticate with a provider (or
  export an API key like `ANTHROPIC_API_KEY`). Update later with `pi update`.
- **Neovim:** run `nvim` once after install — NvChad bootstraps its plugins on
  first launch. Switch themes with `:NvChad theme` (Catppuccin is built in).
- **tmux:** prefix is `C-Space`, `Alt+H`/`Alt+L` switch windows. Add plugins by
  editing `~/.config/tmux/tmux.conf` and running the TPM installer.
- **ufw:** SSH is allowed before the firewall is enabled, so you won't be
  locked out. Verify with `ufw status`.

## Security

These scripts contain no credentials, hostnames, or personal key names. The
server address is passed as a command-line argument to `upload_to_server.sh`,
never hardcoded. Keep your private key and any server details out of the repo.
