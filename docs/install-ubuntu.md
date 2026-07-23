# ubuntu — First Install on Ubuntu 24.04 LTS

This guide walks through setting up the Ubuntu host using standalone Home
Manager: install Nix, first `home-manager switch`, and validate.

Unlike NixOS hosts, standalone HM does not manage the OS — only the user
environment. There is no disko, no impermanence, no systemd units from NixOS
aspects, **and no agenix wiring at all**: `modules/parts/ubuntu.nix` declares
no `age.rekey`, no `age.secrets`, and imports no agenix Home Manager module.
Nothing in this repo's actual flake config ever reads an ubuntu-specific
secret, so there is no host key to generate and no secret to rekey for this
host.

This guide is explicit about which parts are genuinely handled by
`home-manager switch` (Nix-managed: packages, dotfiles, zsh's own
configuration, Sway's own config files) and which parts remain the
**operator's** responsibility at the OS level, entirely outside this repo's
Nix config (graphics drivers, XDG portals, a Polkit agent, PAM/`/etc/shells`
registration, and display-manager session setup). Steps below call this out
explicitly wherever it applies.

---

## Prerequisites

Nix-managed (this repository provides these once you clone it and run
`home-manager switch`):

- This repository cloned on the target machine.

Operator/OS-level (you must handle these yourself; none of them are Nix
outputs):

- Ubuntu 24.04 LTS (x86_64).
- Administrative access (`sudo`).
- A GitHub personal access token (classic, with `repo` scope) for `gh` auth.
- Graphics drivers for your GPU, installed via Ubuntu's own mechanism (e.g.
  `ubuntu-drivers autoinstall` for NVIDIA, or Mesa from the default repos for
  Intel/AMD). Nothing in `aspects.homeManager.sway` installs or configures a
  GPU driver — standalone Home Manager cannot touch kernel modules or system
  packages.
- `dbus-user-session` (typically already installed on Ubuntu Desktop; if
  missing, `sudo apt install dbus-user-session`) — needed for the
  `dbus-run-session` Sway launch path documented under "Starting a Sway
  session" below.
- XDG desktop portals and a Polkit authentication agent, if you want
  screen-sharing/file-picker portals or GUI polkit prompts to work under
  Sway. `modules/home/sway.nix` (the aspect ubuntu imports) declares
  **neither** — both are wired up only in `modules/nixos/sway.nix`'s
  NixOS-only aspect, which standalone HM cannot reach. Install them via apt
  if you need them, e.g. `sudo apt install xdg-desktop-portal
  xdg-desktop-portal-wlr policykit-1-gnome`, and start the portal/polkit
  agent yourself (or via your own systemd user unit) — this repo does not do
  it for you on ubuntu.

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

## Step 3: First Home Manager activation

Build and activate the user environment:

```bash
nix develop '.#'
home-manager switch --flake .#ubuntu
```

The first build downloads and compiles everything (Sway, DMS, all tools and
configuration). This takes 5–15 minutes depending on the internet connection
and machine speed.

## Step 4: Validate

After activation, verify what Home Manager genuinely manages:

- **CLI tools**: `bat --version`, `eza --version`, `jq --version` all work.
- **SSH config**: `ssh soyo` resolves and connects (if on the same network).
- **Zsh configuration**: open a new shell with the Nix-managed zsh directly
  (`~/.nix-profile/bin/zsh`) and confirm aliases/functions/Oh-My-Zsh are
  active, e.g. `alias ll` or `echo $ZSH_VERSION`. Home Manager writes
  `~/.zshrc` directly, so any zsh binary that starts an interactive shell
  sources it.
- **Sway's config file**: `~/.config/sway/config` exists and is
  Nix-managed — but see below for how to actually *start* a Sway session,
  since nothing above makes it appear automatically.

### Zsh is not your login shell yet

`programs.zsh.enable = true` (via `aspects.homeManager.base`) installs and
configures zsh — rc files, Oh-My-Zsh plugins, aliases, everything ubuntu's
assembler pulls in via `base` — into your Nix profile. It **cannot** and
**does not** change your account's login shell (the `/etc/passwd` shell
field): that is an OS-level setting only `chsh` (or an admin editing
`/etc/passwd`) can change, and it is not something `home-manager switch`
touches. After activation, `echo $SHELL` will still show whatever your login
shell was before you ran this guide — it will **not** automatically switch to
a Nix-managed zsh path.

If you want zsh to also be your login shell, this is an **optional
OS-administrator step**, not something HM does or needs to do for its own
zsh configuration to work (see Step 4's zsh validation above, which works
regardless of `$SHELL`). Ubuntu's `chsh`/PAM stack refuses any shell path not
listed in `/etc/shells`, and a raw `/nix/store/<hash>-zsh-<version>/bin/zsh`
path would break that registration on every zsh version bump once the old
store path is garbage-collected. Use the stable Nix profile symlink instead —
this is genuinely what `home-manager switch` itself installs zsh into (its
activation script runs `nix profile install`/`nix-env -i` against your
default user profile, not a raw store path):

```bash
sudo sh -c 'echo "$HOME/.nix-profile/bin/zsh" >> /etc/shells'
chsh -s "$HOME/.nix-profile/bin/zsh"
```

Log out and back in for the new login shell to take effect.

### Starting a Sway session

Ubuntu 24.04's default display manager, GDM3, discovers selectable sessions
by scanning **system** directories — `/usr/share/wayland-sessions/*.desktop`
for Wayland compositors — not a user's Nix profile or home directory.
`aspects.homeManager.sway` (in `modules/home/sway.nix`) configures Sway's own
behavior (keybindings, startup, systemd user services) but generates no such
`.desktop` file anywhere, and standalone Home Manager has no mechanism to
write one into a system directory even if it did. So Sway will **not** appear
as a selectable session on the GDM3 login screen out of the box.

The supported, no-extra-setup way to start it is from a text console,
bypassing GDM's session picker entirely:

1. From the GDM3 login screen, switch to a virtual console (e.g.
   `Ctrl+Alt+F3`) and log in with your normal username/password.
2. Start a Wayland session with its own D-Bus session bus:

   ```bash
   dbus-run-session -- sway
   ```

3. Exit Sway (`$mod+Shift+e` or however you've bound it) to return to the
   console; switch back to GDM3 with `Ctrl+Alt+F1` (or reboot).

If you would rather select Sway from GDM3's login screen, that requires an
**operator/OS-administrator action outside this repo's Nix config** — Nix
cannot write to `/usr/share` from standalone Home Manager. Create the session
file yourself, pointing at the stable Nix profile path (not a raw store
path, for the same reason as the zsh path above):

```bash
sudo tee /usr/share/wayland-sessions/sway-nix.desktop >/dev/null <<'EOF'
[Desktop Entry]
Name=Sway (Nix, home-manager)
Comment=Tiling Wayland compositor managed by Home Manager
Exec=dbus-run-session -- /home/krzysiek/.nix-profile/bin/sway
Type=Application
EOF
```

This is optional, is not created or maintained by `home-manager switch`, and
will need updating manually if you ever move the profile symlink (e.g. a
different username/home directory).

## Known limitations on Ubuntu (vs NixOS hosts)

- **No system-level management.** Standalone HM manages only the user
  environment. OS updates (apt), kernel, drivers, and system services remain
  managed by Ubuntu directly.
- **No persistence module.** `/persist` does not exist; data is stored
  in normal home-directory paths per Ubuntu conventions.
- **No restic/btrbk backups.** Backup is done via a separate tool.
- **No gaming.** Gaming aspects are NixOS-only (Steam, NVIDIA offload, etc.).
- **No Polkit agent or XDG portals.** Both are declared only in
  `modules/nixos/sway.nix`'s NixOS-only aspect (see Prerequisites above);
  install and start them yourself via apt if you need them.
- **No display-manager session registration.** See "Starting a Sway
  session" above.
- **No automatic login-shell change.** See "Zsh is not your login shell yet"
  above.
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
