# Workstation Setup Guide

This document describes the complete workstation setup for zbook (HP ZBook Studio G10) running NixOS with Sway.

## Overview

The workstation uses:
- **OS**: NixOS (unstable channel)
- **Desktop**: Sway (Wayland compositor) with Dank Material Shell (DMS)
- **Terminal**: Ghostty with Zsh + Oh-My-Zsh
- **Editor**: Neovim (primary), Zed (secondary)
- **Shell**: Zsh with extensive tooling

## Cross-Platform Availability

This configuration is shared across multiple hosts. Not all tools are available on all platforms:

### zbook (NixOS) — Full Configuration

- **Desktop**: Sway + DMS + all Wayland tools
- **Gaming**: Steam, Heroic, Lutris, MangoHUD
- **Virtualization**: Podman, libvirtd, virt-manager, distrobox
- **System**: All NixOS modules, persistence, backups
- **All CLI and desktop tools available**

### macbook (nix-darwin) — Assembler + CI evaluation only; hardware deploy pending

- **Desktop**: Aerospace (tiling WM, similar to Sway)
- **Terminal**: macOS's built-in Terminal.app, launched by Aerospace's
  `Cmd+Return` via `open -n -a Terminal` — not Ghostty. Ghostty's nixpkgs
  package declares only Linux platforms in `meta.platforms` (no
  `aarch64-darwin`), so it cannot be installed on macbook; Terminal.app
  ships with macOS and needs no Nix package or Home Manager module. The
  `-n` flag spawns a new Terminal.app instance/window on every keypress
  (AeroSpace's own docs give this exact invocation as the canonical
  example); without it, `open -a Terminal` would just refocus an existing
  window instead of tiling a fresh one, matching Sway's `Mod+Return`
  behavior on zbook/ubuntu.
- **Shell**: Zsh, but as the *login* shell it is macOS's own `/bin/zsh`,
  not the Nix-store one — see [`docs/install-macbook.md`](install-macbook.md)
  Step 6. Home Manager's zsh configuration (aliases, functions, Oh-My-Zsh)
  still applies once that shell sources `~/.zshrc`.
- **Editors**: Neovim, Zed
- **All CLI tools available** (cross-platform packages)
- **Not available**: Sway, DMS, Wayland tools, gaming, Podman, virt-manager,
  distrobox, Firefox, Bitwarden, Signal, Obsidian (all four are Linux-only
  in this repo's Home Manager aspects — see the matrix below; install the
  regular macOS app yourself if you need one, outside of Nix)

### ubuntu (Standalone Home Manager) — Assembler + CI evaluation only; hardware deploy pending

- **Desktop**: Sway + DMS config is Home Manager-managed (the config files
  themselves), but **not automatically startable** — Ubuntu's GDM3 discovers
  sessions from `/usr/share/wayland-sessions/*.desktop`, a system directory
  standalone Home Manager cannot write to. There is no display-manager
  session registration anywhere in this repo for ubuntu. See
  [`docs/install-ubuntu.md`](install-ubuntu.md)'s "Starting a Sway session"
  for the supported console `dbus-run-session sway` path (and an optional,
  operator-created system session file if you want GDM3 login-screen
  selection instead).
- **Terminal**: Ghostty, Zsh, same shell config
- **Shell**: Zsh's configuration (aliases, functions, Oh-My-Zsh) is
  Home Manager-managed, but the *login* shell (`$SHELL`, `/etc/passwd`) is
  **not** changed automatically — see
  [`docs/install-ubuntu.md`](install-ubuntu.md)'s "Zsh is not your login
  shell yet" for the optional `chsh` step and the stable
  `~/.nix-profile/bin/zsh` path to use with it.
- **Editors**: Neovim, Zed
- **All CLI tools available** (Home Manager packages)
- **Not available**: NixOS modules, persistence, backups, gaming, Podman,
  virt-manager, distrobox, Firefox (only declared in `aspects.nixos.desktop`,
  a NixOS-only aspect namespace unreachable from standalone Home Manager —
  install it via `apt` if needed, outside of Nix), Polkit agent, XDG portals
  (both only declared in `modules/nixos/sway.nix`'s NixOS-only
  `aspects.nixos.sway`, not the `aspects.homeManager.sway` aspect ubuntu
  imports — install and start them via `apt` yourself if you need them, see
  [`docs/install-ubuntu.md`](install-ubuntu.md)'s Prerequisites), a
  display-manager session file (see the Desktop bullet above)

### Tool Availability Matrix

| Category | zbook | macbook | ubuntu |
|----------|-------|---------|--------|
| **Shell & CLI** | ✓ | ✓ | ✓ |
| **Development tools** | ✓ | ✓ | ✓ |
| **AI tools** | ✓ | ✓ | ✓ |
| **Editors (nvim, zed)** | ✓ | ✓ | ✓ |
| **Sway + DMS** | ✓ | ✗ | ✓ |
| **Aerospace** | ✗ | ✓ | ✗ |
| **Wayland tools** | ✓ | ✗ | ✓ |
| **Gaming** | ✓ | ✗ | ✗ |
| **Podman** | ✓ | ✗ | ✗ |
| **libvirtd/virt-manager** | ✓ | ✗ | ✗ |
| **distrobox** | ✓ | ✗ | ✗ |
| **NixOS modules** | ✓ | ✗ | ✗ |
| **Persistence** | ✓ | ✗ | ✗ |
| **Backups (restic/btrbk)** | ✓ | ✗ | ✗ |
| **NVIDIA offload** | ✓ | ✗ | ✗ |
| **Polkit agent** | ✓ | ✗ | ✗ |
| **XDG portals** | ✓ | ✗ | ✗ |
| **Firefox** | ✓ | ✗ | ✗ |
| **Bitwarden** | ✓ | ✗ | ✓ |
| **Signal** | ✓ | ✗ | ✓ |
| **Obsidian** | ✓ | ✗ | ✓ |

Firefox, Bitwarden, Signal, and Obsidian are only declared in
`modules/home/desktop.nix`'s Linux-only `lib.optionals stdenv.isLinux [...]`
guard (Bitwarden/Signal/Obsidian) or in `modules/nixos/desktop.nix`'s
`aspects.nixos.desktop` (Firefox), a NixOS-only aspect namespace that
neither macbook (nix-darwin) nor ubuntu (standalone Home Manager, no NixOS)
can import. None of these four are declaratively managed by this repo on
macbook; Firefox additionally is not declaratively managed on ubuntu. Where
real hardware needs one of these apps and this repo doesn't manage it,
install the regular macOS/Ubuntu app yourself (App Store/`.dmg`/`apt`) —
it is operator-installed, not Nix-managed, on that host.

The Polkit agent (`polkit_gnome` and its systemd user service) and XDG
portals (`xdg.portal.enable` plus `xdg-desktop-portal-wlr`/`-gtk`) are
declared only in `modules/nixos/sway.nix`'s NixOS-only `aspects.nixos.sway`
aspect, not the `aspects.homeManager.sway` aspect ubuntu imports. Verified
via `nix eval`: zbook's real NixOS config has `xdg.portal.enable = true`
and a `polkit-gnome-authentication-agent` systemd user service; ubuntu's
real evaluated Home Manager config has `xdg.portal.enable = false` and no
polkit service at all. Both are therefore unavailable on macbook and
ubuntu alike, not just macbook.

## Initial Setup

### 1. Install NixOS

Follow the [NixOS installation guide](https://nixos.org/manual/nixos/stable/index.html#sec-installation).

### 2. Clone Configuration

```bash
cd /home/krzysiek
git clone git@github.com:knirski/nix-config.git
cd nix-config
```

### 3. Deploy Configuration

```bash
just deploy zbook
```

### 4. Reboot

After first deploy, reboot to ensure NVIDIA drivers load correctly:

```bash
sudo reboot
```

## Shell Configuration

### Zsh Plugins

The following Oh-My-Zsh plugins are enabled:
- `git` - Git aliases and functions
- `docker` / `docker-compose` - Docker completion
- `sudo` - Double-esc to prepend sudo
- `copyfile` - Copy file contents to clipboard
- `dirhistory` - Navigate directory history
- `extract` - Extract any archive
- `history` - History management
- `z` - Frecent directory jumping
- `colored-man-pages` - Colorized man pages

### Shell Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `ll` | `eza -la --icons --git` | Long listing with git status |
| `la` | `eza -a --icons` | List all files |
| `ls` | `eza --icons` | List files |
| `lt` | `eza -la --icons --git --tree --level=2` | Tree view |
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `g` | `git` | Git shortcut |
| `gst` | `git status` | Git status |
| `gco` | `git checkout` | Git checkout |
| `gd` | `git diff` | Git diff |
| `gl` | `git pull` | Git pull |
| `gp` | `git push` | Git push |
| `gc` | `git commit` | Git commit |
| `nrs` | `sudo nixos-rebuild switch --flake .` | NixOS rebuild switch |
| `hms` | `home-manager switch --flake .` | Home Manager switch |
| `cat` | `bat` | Better cat |
| `grep` | `ripgrep` | Better grep |
| `find` | `fd` | Better find |
| `top` | `btop` | Better top |

### Shell Functions

| Function | Description |
|----------|-------------|
| `mkcd <dir>` | Create directory and cd into it |
| `extract <file>` | Extract any archive |
| `portkill <port>` | Kill process using port |
| `weather [location]` | Get weather |
| `cheat <command>` | Get cheat sheet |

## Development Tools

### Git Configuration

- **Commit signing**: SSH-based signing enabled
- **Aliases**: `lg` (log graph), `st` (status), `co` (checkout), etc.
- **Delta**: Used as pager for syntax-highlighted diffs
- **Pull strategy**: Rebase by default

### GitHub CLI

- **gh-dash**: Dashboard for PRs, issues, repos
- **Editor**: Neovim
- **Protocol**: SSH

### Lazygit

- **Theme**: Catppuccin Mocha
- **Pager**: Delta for diffs
- **Sign-off**: Enabled by default

### Neovim

Full IDE-like configuration with:
- **LSP**: nil (Nix), lua_ls, pyright, ts_ls, rust_analyzer, gopls
- **Treesitter**: Syntax highlighting for Nix, Lua, Python, JavaScript, TypeScript, Rust, Go, Bash, JSON, YAML, TOML, Markdown
- **Completion**: nvim-cmp with LSP, buffer, path sources
- **Fuzzy finder**: Telescope
- **File explorer**: Neo-tree
- **Status line**: Lualine
- **Git**: Gitsigns
- **Theme**: Catppuccin Mocha

### AI Tools

- **claude-code**: Claude CLI
- **codex**: OpenAI Codex CLI
- **opencode**: OpenCode CLI
- **command-code**: Command Code CLI

## Desktop Environment

### Sway

**Keybindings:**

| Key | Action |
|-----|--------|
| `Mod+Return` | Open terminal (Ghostty) |
| `Mod+Q` | Kill window |
| `Mod+Space` | Spotlight search |
| `Mod+V` | Clipboard history |
| `Mod+X` | Power menu |
| `Mod+N` | Notifications |
| `Mod+F` | Fullscreen |
| `Mod+1-9` | Switch workspace |
| `Mod+Shift+1-9` | Move to workspace |
| `Mod+Print` | Screenshot (full) |
| `Mod+Ctrl+Print` | Screenshot (selection) |
| `XF86AudioRaiseVolume` | Volume up |
| `XF86AudioLowerVolume` | Volume down |
| `XF86MonBrightnessUp` | Brightness up |
| `XF86MonBrightnessDown` | Brightness down |

**Window Rules:**

The following windows float automatically:
- Bitwarden
- Blueman Manager
- pavucontrol
- nwg-displays / nwg-look
- File dialogs (Open/Save)
- Preferences/Settings windows

**Touchpad:**

- Tap-to-click enabled
- Natural scrolling
- Disable while typing
- Pointer acceleration: 0.3

### Dank Material Shell (DMS)

DMS provides:
- **Bar**: Launcher, workspace switcher, focused window, system tray, clock, weather, battery, control center
- **Spotlight**: Application launcher (Mod+Space)
- **Clipboard**: History manager (Mod+V)
- **Notifications**: Notification center (Mod+N)
- **Power menu**: Logout, reboot, shutdown, lock (Mod+X)
- **Lock screen**: Fade-to-lock with password

### Fonts

- **UI**: Inter Variable
- **Monospace**: JetBrains Mono Nerd Font
- **Code**: Fira Code Nerd Font
- **Emoji**: Noto Color Emoji
- **Symbols**: Symbols Only Nerd Font

## System Tools

### CLI Tools (Cross-Platform)

All CLI tools below are available on zbook, macbook, and ubuntu via Home Manager modules:

| Tool | Purpose |
|------|---------|
| `eza` | Modern ls |
| `bat` | Modern cat with syntax highlighting |
| `fd` | Modern find |
| `ripgrep` | Modern grep |
| `fzf` | Fuzzy finder |
| `skim` | Rust fuzzy finder |
| `zoxide` | Smart cd |
| `btop` | System monitor |
| `bottom` | System monitor (alternative) |
| `procs` | Modern ps |
| `du-dust` | Modern du |
| `ncdu` | Interactive disk usage |
| `dogdns` | Modern dig |
| `hyperfine` | Benchmarking |
| `yq` | YAML processor |
| `sd` | Modern sed |
| `jq` | JSON processor |
| `lazygit` | Git TUI |
| `lazydocker` | Docker TUI |
| `yazi` | File manager |
| `nnn` | File manager (alternative) |
| `mc` | Midnight Commander |
| `broot` | File manager with fuzzy search |
| `tmux` | Terminal multiplexer |
| `atuin` | Shell history sync |
| `fzf` | Fuzzy finder (Ctrl-R history search) |
| `pay-respects` (via `f` alias) | Command correction (replaces `thefuck`) |
| `navi` | Interactive cheat sheets |
| `tealdeer` | Rust tldr client |
| `fastfetch` | System info |
| `difftastic` | Structural diff |
| `delta` | Syntax-highlighted diff |
| `tldr` | Simplified man pages |

### Nix Tools (NixOS Only)

These tools are only available on NixOS hosts:

| Tool | Purpose |
|------|---------|
| `nix-output-monitor` (nom) | Real-time rebuild progress |
| `nix-tree` | Browse store dependencies |
| `nvd` | Diff system closures |
| `nix-index-database` | Pre-built package database |
| `nh` | NixOS helper |
| `comma` | Run programs without installing |

### Security Tools (Cross-Platform)

| Tool | Purpose |
|------|---------|
| `age` | Encryption |
| `gnupg` | Encryption |
| `lynis` | Security auditing (NixOS only) |
| `bitwarden-desktop` | Password manager (Linux only — zbook, ubuntu; not available on macbook, see the matrix above) |

### Container Tools (NixOS Only)

| Tool | Purpose |
|------|---------|
| `podman` | Rootless containers |
| `docker-cli` | Docker compatibility |
| `distrobox` | Integrate other distros |
| `lazydocker` | Docker TUI |

### Virtualization (NixOS Only)

| Tool | Purpose |
|------|---------|
| `virt-manager` | VM management GUI |
| `libvirtd` | Virtualization daemon |

## Gaming

### Steam

- NVIDIA offload enabled
- Gamescope session available
- Remote play enabled

### Heroic Launcher

- Epic/GOG games
- NVIDIA offload enabled

### Lutris

- Game launcher for various sources

### Gaming Tools

- **MangoHUD**: FPS overlay
- **GOverlay**: MangoHUD GUI
- **ProtonUp-Qt**: Proton GE manager
- **Gamemode**: Automatic game optimization

## Backups

### Restic

Backups run daily to Synology NAS (`czworaczki.home.arpa`):
- **Schedule**: Daily at 02:00
- **Retention**: 7 daily, 4 weekly, 6 monthly
- **Paths**: `/persist`

### Btrbk

Local Btrfs snapshots:
- **Schedule**: Hourly
- **Retention**: 10 hourly, 7 daily

## Monitoring

### System Health

- **smartd**: Disk health monitoring
- **Btrbk**: Btrfs scrub (monthly)
- **Free space**: Hourly check with ntfy alerts

### Notifications

- **ntfy**: Push notifications for failures
- **DMS**: Desktop notifications

## SSH Configuration

- **Multiplexing**: ControlMaster/ControlPath for connection reuse
- **Agent forwarding**: Enabled for trusted homelab hosts (soyo, zbook)
- **Host key verification**: StrictHostKeyChecking enabled by default
- **Key management**: AddKeysToAgent for automatic key loading

### Security Notes

- ForwardAgent is enabled for trusted homelab LAN hosts only
- Use `ssh -A` for ad-hoc forwarding to untrusted hosts
- GitHub uses `accept-new` for host key verification

## Networking

### Tailscale

- Mesh VPN for remote access
- MagicDNS enabled
- Subnet routing for LAN access

### DNS

- **Blocky**: Ad-blocking DNS (on soyo)
- **systemd-resolved**: Local DNS resolver

## Maintenance

### Regular Tasks

1. **Update flake inputs**:
   ```bash
   nix flake update
   ```

2. **Deploy changes**:
   ```bash
   just deploy zbook
   ```

3. **Run healthcheck**:
   ```bash
   just healthcheck zbook
   ```

4. **Check backups**:
   ```bash
   just backup-status zbook
   ```

### Garbage Collection

- **Nix store**: Weekly optimization
- **Old generations**: Kept for 30 days

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues and solutions.
