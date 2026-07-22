# ubuntu — First Install on Ubuntu 24.04 LTS

This guide walks through setting up the Ubuntu host using standalone Home
Manager: install Nix, bootstrap secrets, first `home-manager switch`, and
validate.

Unlike NixOS hosts, standalone HM does not manage the OS — only the user
environment. There is no disko, no impermanence, no systemd units from NixOS
aspects.

---

## Prerequisites

- Ubuntu 24.04 LTS (x86_64).
- Administrative access (`sudo`).
- A GitHub personal access token (classic, with `repo` scope) for `gh` auth.
- Your SSH private key matching `secrets/agenix-master.pub` for agenix rekeying.
- This repository cloned on the target machine.

## Step 1: Install Nix

Install Nix using the Determinate installer (recommended for clean uninstall):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
  | sh -s -- install
```

After installation, either restart your shell or source the profile:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Verify Nix works with flakes:

```bash
nix --version
nix eval nixpkgs#lib.version --raw
```

## Step 2: Clone the repository

```bash
cd ~
git clone git@github.com:knirski/nix-config.git
cd nix-config
```

## Step 3: Generate an SSH host key (for agenix)

Standalone HM does not provide system-level SSH host keys. Create one so the
Ubuntu host can be enrolled as an agenix recipient:

```bash
sudo install -d -m 700 /etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
```

Extract the public key:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

Copy this value; it will be needed in the next step.

## Step 4: Enroll the ubuntu host in agenix and rekey secrets

Create the ubuntu public key file:

```bash
echo 'ssh-ed25519 AAAA...' > secrets/ubuntu.pub
```

Replace `AAAA...` with the key from Step 3. Then rekey all secrets so the
ubuntu host can decrypt them:

```bash
nix develop '.#' -c agenix rekey
```

Commit the new host key and rekeyed secrets:

```bash
git add secrets/ubuntu.pub secrets/rekeyed/ubuntu/
git commit -m "feat: enroll ubuntu agenix recipient and rekey secrets"
```

## Step 5: First Home Manager activation

Build and activate the user environment:

```bash
nix develop '.#'
home-manager switch --flake .#ubuntu
```

The first build downloads and compiles everything (Sway, DMS, all tools and
configuration). This takes 5–15 minutes depending on the internet connection
and machine speed.

After the first activation, log out and back in (or restart your display
manager) to pick up the new desktop session.

## Step 6: Validate

After activation, verify:

- **Sway**: The Sway + DMS desktop session is available in your display manager
- **Zsh**: `echo $SHELL` should show a Nix-managed Zsh path
- **CLI tools**: `bat --version`, `eza --version`, `jq --version` all work
- **SSH config**: `ssh soyo` resolves and connects (if on the same network)

## Known limitations on Ubuntu (vs NixOS hosts)

- **No system-level management.** Standalone HM manages only the user
  environment. OS updates (apt), kernel, drivers, and system services remain
  managed by Ubuntu directly.
- **No persistence module.** `/persist` does not exist; data is stored
  in normal home-directory paths per Ubuntu conventions.
- **No restic/btrbk backups.** Backup is done via a separate tool.
- **No gaming.** Gaming aspects are NixOS-only (Steam, NVIDIA offload, etc.).
- **Tailscale** is operator-installed (apt or GUI app) — the HM module only
  configures SSH for tailnet access.

## Subsequent deploys

For routine updates:

```bash
cd ~/nix-config
git pull
home-manager switch --flake .#ubuntu
```

Or use `just deploy ubuntu` (which runs `home-manager switch` under the hood).
