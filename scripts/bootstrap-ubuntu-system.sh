#!/usr/bin/env bash
# Applies the Ubuntu-level setup Home Manager cannot own.
#
# These files live outside every Home Manager generation, so a reinstall (or
# anyone who deletes one by accident) silently loses a working session: no
# Wayland greeter, no GL for Nix programs, no session entry in GDM, or no
# DDC/CI access for monitor control. Each failure looks like something else
# -- a black screen, "Failed to create EGL display", Sway simply missing from
# the session list, or ddcutil "Permission denied" -- so rediscovering them
# costs far more than reapplying them.
#
# Idempotent: every step checks before writing and reports what it did.
# Requires sudo for the four system steps; the wallpaper step does not.
#
# See docs/ubuntu-adaptations.md for why each one is needed.
set -euo pipefail

USER_NAME=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
changed=0
needs_relogin=0

say() { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }

step "1/5  GDM must run Wayland"
if [ ! -f /etc/gdm3/custom.conf ]; then
  say "SKIP  /etc/gdm3/custom.conf not present (not a GDM system?)"
elif grep -qE '^WaylandEnable=false' /etc/gdm3/custom.conf; then
  sudo sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' /etc/gdm3/custom.conf
  say "DONE  commented WaylandEnable=false (restart gdm3 to apply)"
  changed=1
else
  say "OK    Wayland already enabled"
fi

step "2/5  /run/opengl-driver for Nix OpenGL"
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

step "3/5  GDM session entry"
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

step "4/5  Desktop wallpaper"
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

step "5/5  i2c-dev + Logitech hidraw access for desk peripherals"
# The desk-switch keybinding (Mod4+Insert / Mod4+Home) uses ddcutil over
# DDC/CI and solaar-cli over the Logitech receiver's hidraw node. Ubuntu's
# kernel does not auto-load i2c-dev, the /dev/i2c-* nodes are root:root 0600
# without a udev rule, and the Nix solaar package (unlike the apt one) ships
# no udev rules for /dev/hidraw*. NixOS hosts get all of this via
# hardware.i2c and hardware.logitech.wireless (see modules/nixos/sway.nix and
# modules/nixos/logitech.nix); standalone Home Manager cannot own system
# files, so they live here.
modconf=/etc/modules-load.d/i2c-dev.conf
if [ -f "$modconf" ] && grep -qE '^i2c-dev$' "$modconf"; then
  say "OK    $modconf already loads i2c-dev"
else
  printf 'i2c-dev\n' | sudo tee "$modconf" >/dev/null
  say "DONE  wrote $modconf"
  changed=1
fi
if ! ls /dev/i2c-* >/dev/null 2>&1; then
  sudo modprobe i2c-dev
  say "DONE  loaded i2c-dev"
  changed=1
fi
udev_rule=/etc/udev/rules.d/91-i2c-ddcutil.rules
want_rule="SUBSYSTEM==\"i2c-dev\", GROUP=\"$USER_NAME\", MODE=\"0660\""
if [ -f "$udev_rule" ] && grep -qF "GROUP=\"$USER_NAME\"" "$udev_rule"; then
  say "OK    $udev_rule grants i2c-dev to $USER_NAME"
else
  printf '%s\n' "$want_rule" | sudo tee "$udev_rule" >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=i2c-dev
  say "DONE  wrote $udev_rule (i2c nodes now readable by $USER_NAME)"
  changed=1
fi
hidraw_rule=/etc/udev/rules.d/92-logitech-hidraw.rules
want_hidraw="KERNEL==\"hidraw*\", SUBSYSTEM==\"hidraw\", ATTRS{idVendor}==\"046d\", MODE=\"0660\", GROUP=\"$USER_NAME\""
if [ -f "$hidraw_rule" ] && grep -qF "ATTRS{idVendor}==\"046d\"" "$hidraw_rule"; then
  say "OK    $hidraw_rule grants Logitech hidraw to $USER_NAME"
else
  printf '%s\n' "$want_hidraw" | sudo tee "$hidraw_rule" >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw
  say "DONE  wrote $hidraw_rule (Logitech hidraw nodes now readable by $USER_NAME)"
  changed=1
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
