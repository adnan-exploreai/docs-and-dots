# docs-and-dots

Bootstrap scripts for a fresh Debian 12 server: user setup, shell + tooling
with a Catppuccin theme, AI tooling, and Docker.

## Files

| File | Purpose |
| --- | --- |
| `upload_to_server.sh` | Upload your SSH public key and the setup scripts to a fresh server |
| `setup_debian.sh` | Main bootstrap: user, packages, shell, AI tooling, Docker, toolchains |
| `install_neovim.sh` | Standalone Neovim + NvChad installer (called by `setup_debian.sh`) |

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
5. **AI tooling** — herdr (agent terminal runtime), opencode (AI coding agent)
6. **Containers** — Docker Engine + Compose plugin from Docker's official repo
7. **Dev toolchains** — rustup, Python + uv, Neovim + NvChad, Node.js 20 LTS + npm
8. **Monitoring** — btop, ncdu, unattended security upgrades
9. **Security** — ufw firewall (SSH allowed, rest denied) + fail2ban
10. **Misc CLI** — yq, sqlite3

## Notes

- **Root only in the beginning:** `setup_debian.sh` creates a sudo user for
  daily use; the rest of the script configures that account.
- **SSH key lookup:** `setup_debian.sh` auto-detects a public key among
  `id_ed25519.pub`, `id_rsa.pub`, and `id_ecdsa.pub` in `/root/.ssh` or
  `$HOME/.ssh`. Override with `SSH_KEY_SOURCE=/path/to/key.pub`.
- **Docker group:** the target user is added to `docker`; log out/in for it to
  take effect.
- **Neovim:** run `nvim` once after install — NvChad bootstraps its plugins on
  first launch. Switch themes with `:NvChad theme` (Catppuccin is built in).
- **ufw:** SSH is allowed before the firewall is enabled, so you won't be
  locked out. Verify with `ufw status`.

## Security

These scripts contain no credentials, hostnames, or personal key names. The
server address is passed as a command-line argument to `upload_to_server.sh`,
never hardcoded. Keep your private key and any server details out of the repo.
