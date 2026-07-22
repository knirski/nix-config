# macbook — First Install on Apple Silicon

This guide walks through provisioning the macbook from a stock macOS system:
install Nix, bootstrap secrets, first `darwin-rebuild`, and validate.

> **Status:** The macbook assembler and CI evaluate; hardware deploy is
> pending. The runbook is ready to follow once hardware is available.

---

## Prerequisites

- An Apple Silicon Mac (aarch64).
- macOS Sequoia or later.
- Administrative access (`sudo`).
- A GitHub personal access token (classic, with `repo` scope) for `gh` auth.
- Your SSH private key matching `secrets/agenix-master.pub` for agenix rekeying.
  Set up the master identity symlink:
  ```bash
  sudo install -d -m 755 /etc/agenix-rekey
  sudo ln -sfn "$HOME/.ssh/agenix_master" /etc/agenix-rekey/master-identity
  ```
  See [`docs/secrets.md`](secrets.md) for details.
- This repository cloned on the target machine.

## Step 1: Install Nix

Install Nix using the Determinate installer (recommended on macOS for its
clean uninstall path and Sequoia compatibility):

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

macOS does not generate SSH host keys by default. Create one so the macbook can
be enrolled as an agenix recipient:

```bash
sudo install -d -m 700 /etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
```

Extract the public key:

```bash
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

Copy this value; it will be needed in the next step.

## Step 4: Enroll the macbook in agenix and rekey secrets

> **⚠️ Blocked — agenix wiring is disabled in `modules/parts/macbook.nix`.**
> The age/rekey configuration is commented out until the macbook gets hardware.
> Once uncommented, follow the steps below; until then, secrets are not
> required for evaluation-only CI builds.

Create the macbook public key file:

```bash
echo 'ssh-ed25519 AAAA...' > secrets/macbook.pub
```

Replace `AAAA...` with the key from Step 3. Then rekey all secrets so the
macbook can decrypt them:

```bash
nix develop '.#' -c agenix rekey
```

Commit the new host key and rekeyed secrets:

```bash
git add secrets/macbook.pub secrets/rekeyed/macbook/
git commit -m "feat(secrets): enroll macbook agenix recipient and rekey secrets"
```

## Step 5: First darwin-rebuild

Build and activate the system configuration:

```bash
nix develop '.#'
darwin-rebuild switch --flake .#macbook
```

The first build downloads and compiles everything (including a full nix-darwin
system). This takes 10–30 minutes depending on the internet connection and
machine speed.

After the first activation, reboot to confirm the system comes up cleanly:

```bash
sudo reboot
```

## Step 6: Validate

After reboot, verify:

- **Hostname**: `scutil --get HostName` → `macbook`
- **Zsh**: `echo $SHELL` → `/run/current-system/sw/bin/zsh`
- **Git**: `git --version`
- **macOS defaults**: Dock is hidden; fast key repeat enabled
- **Aerospace**: Launch the Aerospace tiling window manager and verify it
  responds to keyboard shortcuts

## Known limitations on macOS (vs NixOS hosts)

- **No impermanence.** macOS uses APFS natively; there is no Nix-managed root
  wipe or `/persist` bind-mount.
- **No systemd.** nix-darwin uses `launchd`; systemd units from NixOS aspects
  do not apply.
- **Tailscale is operator-installed.** The Tailscale GUI app is installed
  separately; the nix-darwin aspect only configures SSH for tailnet access.
- **No restic or btrbk backups.** Backup is done via Time Machine or a
  third-party tool.
- **No gaming.** No NVIDIA GPU, no DXVK, no Steam (these aspects are
  x86_64-linux NixOS only).

## Subsequent deploys

For routine updates:

```bash
cd ~/nix-config
git pull
darwin-rebuild switch --flake .#macbook
```

Or use `just deploy macbook` (which runs `darwin-rebuild switch` under the
hood).
