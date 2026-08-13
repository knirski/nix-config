# Upgrading Ubuntu: 24.04 LTS → 26.04 LTS

This runbook prepares the `ubuntu` host for an in-place
`do-release-upgrade` from 24.04 LTS to 26.04 LTS and, crucially, verifies the
[Ubuntu ↔ Nix surface](ubuntu-nix-surface.md) afterwards — the upgrade replaces
Ubuntu's half of every crossing point (kernel, Mesa, GDM, systemd, apt
packages) while the Nix side survives untouched.

The repository's Nix configuration needs **no changes** for the upgrade:
`stateVersion = "26.11"` in `modules/parts/ubuntu.nix` is a Home Manager state
version — set once per HM state, not per OS release — and `nixpkgs-unstable`
already tracks current software. This runbook exists because the *surface* is
partly Ubuntu-owned and can drift.

An in-place LTS → LTS upgrade is offered only once the 26.04.1 point release is
published (Ubuntu's standard policy, normally a few months after 26.04.0).
Until then `do-release-upgrade` reports no new release — that is expected, not
a failure.

## What the upgrade does and does not touch

| Component | Survives? | Notes |
| --- | --- | --- |
| `/nix`, `nix-daemon`, Determinate-installer state | Yes | plain directories and a systemd service; nothing release-specific |
| `~/.nix-profile`, Home Manager generations | Yes | `~/.local/state/home-manager` is untouched |
| HM-managed dotfiles (`~/.zshrc`, `~/.config/…`, `~/.local/bin/sway-ubuntu-session`) | Yes | generated anew on the next `home-manager switch` anyway |
| `/etc/tmpfiles.d/nix-opengl-driver.conf` | Yes | not owned by any package |
| `/usr/share/wayland-sessions/sway-nix.desktop` | Yes | not owned by any package; dpkg does not clean unowned files |
| `/etc/gdm3/custom.conf` | Yes, with a prompt | a conffile of `gdm3`; the upgrader (ucf) may ask whether to replace it — **keep the local version** |
| apt packages (`dbus-user-session`, `xdg-desktop-portal*`, `swaylock`, `tailscale`) | Yes | still in the 26.04 archive; third-party apt sources may be *disabled* by the upgrader (see below) |
| Removed snaps | Yes | the upgrade does not reinstall `slack`/`code`/`intellij-idea`/`spotify`/`bitwarden` |
| `~/.envvars`, SSH keys, browser profiles | Yes | plain home-directory data |
| Kernel, Mesa/libglvnd, GDM/GNOME, systemd | Replaced | new release versions — this is the surface to verify |

## Before — pre-flight checklist

1. **Take a fresh backup** with the machine's usual mechanism. There is no
   in-place downgrade for an OS upgrade; if anything goes wrong, restoring
   means a backup restore. This is the one non-negotiable step.
2. **Free disk space.** `df -h /` — the upgrader needs several GB for the new
   packages and the archive cache. Clean with `sudo apt autoremove` first if
   tight.
3. **Get the Nix side to a known-good, current state:**
   ```bash
   git -C ~/repos/external/git/knirski/nix-config pull
   just deploy ubuntu
   just bootstrap-ubuntu-system   # expect "Nothing to do"
   just healthcheck ubuntu        # expect all [PASS]
   ```
   CI should also be green on `main` (`build-ubuntu` job), so the activation
   package the machine will use is cacheable.
4. **Fully update 24.04 first** — `do-release-upgrade` refuses to run against
   an outdated release:
   ```bash
   sudo apt update && sudo apt full-upgrade
   ```
   If `do-release-upgrade` is missing (minimal installs):
   `sudo apt install update-manager-core`.
5. **Confirm the new release is offered:**
   ```bash
   do-release-upgrade -c
   ```
   If it says no new release, the 26.04.1 point release is not published yet.
6. **Plan the session.** Run the upgrade from a TTY or over SSH (inside
   `tmux`/`screen`): GDM and your Sway session are restarted during the
   upgrade, and the machine must not suspend. Plug in power.

## During

- Answer conffile prompts sensibly: for `/etc/gdm3/custom.conf` **keep the
  local version** — the bootstrap script normalizes it either way, and keeping
  it avoids surprises.
- Note which third-party apt sources the upgrader disables (it renames them to
  `.disabled` under `/etc/apt/sources.list.d/` — for this machine, tailscale's
  repo if it was installed from there). Re-enable them after the upgrade.
- The machine will reboot into 26.04 at the end.

## After — post-upgrade verification

Work down this list; everything is deliberately mapped to the
[surface](ubuntu-nix-surface.md).

1. **OS.** `lsb_release -a` → 26.04.x; `uname -r` → new kernel.
2. **Nix survived.**
   ```bash
   nix --version
   systemctl is-active nix-daemon
   nix eval nixpkgs#lib.version --raw
   ```
3. **Re-apply the surface** — the single most important step:
   ```bash
   just bootstrap-ubuntu-system
   ```
   Either "Nothing to do" (everything survived) or it repairs the three system
   files. Re-run it after the first reboot, since `/run` is a tmpfs and the
   `/run/opengl-driver` symlink exists only if the tmpfiles rule did.
4. **Apt packages still present:**
   ```bash
   apt list --installed | grep -E 'dbus-user-session|xdg-desktop-portal|swaylock|tailscale'
   ```
   Re-enable and re-install anything the upgrader disabled; `tailscale up`
   after re-enabling its source.
5. **Login shell.** `getent passwd knirski` shows `~/.nix-profile/bin/zsh` and
   `/etc/shells` still lists it (an OS upgrade does not reset these, but
   verify — the chsh contract lives on the Ubuntu side).
6. **Re-activate Home Manager on the new OS:**
   ```bash
   just deploy ubuntu
   ```
7. **Whole-host check:**
   ```bash
   just healthcheck ubuntu
   ```
8. **Session-level manual checks** — log in as **Sway (Nix, Home Manager)**
   from GDM and verify:
   - the session entry appears in the GDM list and Sway maps `eDP-1` and the
     external panel;
   - `systemctl --user status dms.service dcal.service` — both active;
   - a Nix GL app maps a window (Slack or VS Code) — `/run/opengl-driver` is
     working;
   - no `safeStorage`/`basic_text` warnings from Electron apps — the keyring is
     unlocked by PAM and the `--password-store` overlay held;
   - `ssh-add -l` lists the five keys — the gcr agent is the one serving
     `SSH_AUTH_SOCK`;
   - a signed git commit works — the gpg-agent signing override still applies;
   - `Mod+Print` screenshot and a GTK file dialog work — portals;
   - `Mod+Ctrl+l` locks with swaylock and the password unlocks — PAM path;
   - the wallpaper is still set (DMS IPC alive).

## Known risks and watch items on 26.04

- **New GDM.** Recent GDM versions prefer a Wayland greeter — fine on this
  machine (Intel-only display, no NVIDIA kernel module; the greeter holding DRM
  master is exactly what the `custom.conf` edit prevents). Verify the greeter
  reaches the session picker and `sway-nix.desktop` still shows up.
- **New kernel.** The iGPU's PCI address (`00:02.0`) is stable across kernel
  generations, and the launcher falls back to auto-discovery if the
  `/dev/dri/by-path` node is ever missing — the session still starts either
  way.
- **New systemd.** HM user units are version-agnostic; the
  `ConditionEnvironment`/`sway-session.target` gating is unchanged.
- **New Ubuntu Mesa.** Invisible to Nix programs (their libglvnd searches
  `/run/opengl-driver` first; Ubuntu's libglvnd has no such path) and Nix Mesa
  is invisible to Ubuntu binaries — the two GL stacks do not interfere.
- **Third-party apt sources** may be disabled by the upgrader; tailscale is the
  one to re-enable on this machine.
- **Snap removals** are not undone, but verify `snap list` shows none of the
  five removed apps if you see stray launcher entries.

## If something breaks

| Layer | Recovery |
| --- | --- |
| Surface files (session entry, GL, greeter) | `just bootstrap-ubuntu-system` repairs all three; restart `gdm3` if the greeter was the casualty |
| Nix side | `just deploy ubuntu`; for a rollback, check out an older commit of this repo and switch again — Home Manager generations only move forward |
| OS side | no in-place downgrade exists; restore from the pre-flight backup |

## Related

- [The Ubuntu ↔ Nix surface](ubuntu-nix-surface.md) — the boundary this
  runbook verifies.
- [`docs/install-ubuntu.md`](install-ubuntu.md) — first install.
- [`docs/ubuntu-adaptations.md`](ubuntu-adaptations.md) — the Ubuntu-level
  setup checklist each item above maps to.
