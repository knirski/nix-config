#!/usr/bin/env bash
# Applies the Ubuntu-level setup Home Manager cannot own.
#
# Three files live outside every Home Manager generation, so a reinstall (or
# anyone who deletes one by accident) silently loses a working session: no
# Wayland greeter, no GL for Nix programs, or no session entry in GDM. Each
# failure looks like something else -- a black screen, "Failed to create EGL
# display", or Sway simply missing from the session list -- so rediscovering
# them costs far more than reapplying them.
#
# Idempotent: every step checks before writing and reports what it did.
# Requires sudo for the three system files; the wallpaper step does not.
#
# See docs/ubuntu-adaptations.md for why each one is needed.
set -euo pipefail

USER_NAME=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
changed=0
needs_relogin=0

say() { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

step "1/4  GDM must run Wayland"
if [ ! -f /etc/gdm3/custom.conf ]; then
  say "SKIP  /etc/gdm3/custom.conf not present (not a GDM system?)"
elif grep -qE '^WaylandEnable=false' /etc/gdm3/custom.conf; then
  sudo sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' /etc/gdm3/custom.conf
  say "DONE  commented WaylandEnable=false (restart gdm3 to apply)"
  changed=1
else
  say "OK    Wayland already enabled"
fi

step "2/4  /run/opengl-driver for Nix OpenGL"
tmpfiles=/etc/tmpfiles.d/nix-opengl-driver.conf
want="L+ /run/opengl-driver - - - - $USER_HOME/.nix-profile"
if [ -f "$tmpfiles" ] && grep -qF "$want" "$tmpfiles"; then
  say "OK    $tmpfiles already correct"
else
  printf '%s\n' "$want" | sudo tee "$tmpfiles" >/dev/null
  say "DONE  wrote $tmpfiles"
  changed=1
fi
if [ ! -e /run/opengl-driver ]; then
  sudo systemd-tmpfiles --create "$tmpfiles"
  say "DONE  created /run/opengl-driver"
  changed=1
else
  say "OK    /run/opengl-driver -> $(readlink /run/opengl-driver)"
fi

step "3/4  GDM session entry"
desktop=/usr/share/wayland-sessions/sway-nix.desktop
launcher="$USER_HOME/.local/bin/sway-ubuntu-session"
if [ -f "$desktop" ] && grep -qF "Exec=$launcher" "$desktop"; then
  say "OK    $desktop already points at the launcher"
else
  sudo install -D -m 0644 /dev/stdin "$desktop" <<EOF
[Desktop Entry]
Name=Sway (Nix, Home Manager)
Comment=Tiling Wayland compositor managed by Home Manager
Exec=$launcher
Type=Application
EOF
  say "DONE  wrote $desktop"
  changed=1
  needs_relogin=1
fi
if [ ! -x "$launcher" ]; then
  say "WARN  $launcher is missing -- run the Home Manager switch first"
fi

step "4/4  Desktop wallpaper"
# The shell records this in session.json, which is mutable state it writes
# itself, so it cannot be generated from Nix without freezing the whole file.
wallpaper="$USER_HOME/.local/share/wallpapers/hive-grid.png"
if [ ! -e "$wallpaper" ]; then
  say "SKIP  $wallpaper missing -- run the Home Manager switch first"
elif ! command -v dms >/dev/null 2>&1; then
  say "SKIP  dms not on PATH"
elif [ "$(dms ipc wallpaper get 2>/dev/null)" = "$wallpaper" ]; then
  say "OK    wallpaper already set"
else
  if dms ipc wallpaper set "$wallpaper" >/dev/null 2>&1; then
    say "DONE  wallpaper set"
    changed=1
  else
    say "WARN  could not reach the shell over IPC (is the session running?)"
  fi
fi

printf '\n'
if [ "$changed" -eq 0 ]; then
  echo "Nothing to do -- system-level setup already in place."
else
  echo "Applied changes."
  [ "$needs_relogin" -eq 1 ] && echo "Log out and back in to pick up the session entry."
fi

# Apt packages are deliberately not installed here: they are a one-time
# decision the operator should make knowingly. See docs/ubuntu-adaptations.md
# steps 3, 4 and 9 for dbus-user-session, the portal backends and swaylock.
