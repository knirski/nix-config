# Hyprland desktop

> **Status: Superseded.** This records an earlier Hyprland desktop experiment.
> zbook now runs Sway with Dank Material Shell; see `modules/home/sway.nix` and
> the [learning path](learning/README.md). Do not use the commands or bindings
> below as current operating instructions.

The experiment used [Hyprland](https://hyprland.org), a dynamic Wayland
compositor, in place of a full desktop environment. This document preserves
the evaluated stack and its trade-offs.

## Quick reference

| Action | Binding |
|--------|---------|
| Open terminal | `$mod+Return` |
| App launcher | `$mod+d` |
| Close window | `$mod+q` |
| Lock screen | `$mod+Escape` |
| Fullscreen | `$mod+f` |
| Toggle floating | `$mod+Space` |
| Focus | `$mod+h/j/k/l` |
| Move window | `$mod+Shift+h/j/k/l` |
| Switch workspace | `$mod+1-9` |
| Move to workspace | `$mod+Shift+1-9` |
| Scratchpad | `$mod+,` / `$mod+.` |
| Screenshot (region) | `Print` |
| Screenshot (full) | `$mod+Shift+Print` |
| Show keybinds | `$mod+Shift+/` |
| Color picker | `$mod+Ctrl+c` |
| hy3: split direction | `$mod+v` |
| hy3: adjust ratio | `$mod+r` |
| hy3: group / detach | `$mod+g` / `$mod+Shift+g` |
| hy3: tab / stack mode | `$mod+t` / `$mod+y` |

`$mod` is the Super key (usually the Windows key).

## Tool stack

Every DE component is replaced by a lightweight, Hyprland-native or modern
alternative.

**Window management:** Hyprland + [hy3](https://github.com/outfoxxed/hy3)
plugin for i3/sway-style manual tiling. `$mod+v` toggles split direction,
`$mod+g` groups windows, `$mod+r` resizes ratios — familiar i3 workflow on
Wayland.

| What | Replaces | Why |
|------|----------|-----|
| `hyprlauncher` | GNOME app grid | Hyprland-native launcher/picker |
| `hyprpanel` | GNOME top bar | Full-featured Hyprland panel with workspaces, clock, network, audio, bluetooth, battery |
| `hyprlock` | GNOME lock screen | GPU-accelerated, Catppuccin-themed |
| `hypridle` | GNOME power settings | Auto-lock after 5 min, suspend after 10 |
| `hyprshot` | GNOME screenshot | Uses `hyprctl` for geometry — native region capture |
| `hyprsunset` | Night Light | Timed transitions at sunrise/sunset |
| `hyprpaper` | GNOME wallpaper | Wallpaper daemon (install a wallpaper to use it) |
| `hyprpolkitagent` | polkit-gnome | No GNOME deps, systemd-managed |
| `hyprnotify` | notifications | Routes through `hyprctl notify`, native Hyprland popups |
| `hyprkeys` | — | Keybind reference overlay (`$mod+Shift+/`) |
| `hyprpicker` | — | Color picker (`$mod+Ctrl+c`) |
| `hyprmoncfg` | GNOME Displays | Monitor config GUI |
| `hyprdim` | — | Auto-dim inactive windows |
| `pyprland` | — | Plugin system: scratchpads, expose, lost windows, monitors |

**Outside-Hyprland stack (no native equivalent exists):**

| Tool | Purpose |
|------|---------|
| `ghostty` | GPU-accelerated terminal (Zig) |
| `yazi` | TUI file manager (Rust) |
| `pwvucontrol` | PipeWire volume GUI (Rust) |
| `cliphist` + `wl-clipboard` | Clipboard manager |
| `kanshi` + `wlr-randr` | Auto display profiles on hotplug |
| `nm-applet` | WiFi tray |
| `blueman-applet` | Bluetooth tray |
| `pamixer` + `playerctl` | Volume/media key CLIs |
| `nautilus` | GUI file manager (fallback) |

## Login

Uses **greetd** + **gtkgreet** — a lightweight greeter, no display manager
baggage. Log in at the prompt and Hyprland starts automatically.

If something goes wrong, switch to a TTY with `Ctrl+Alt+F2` and roll back:

```bash
sudo nixos-rebuild switch --flake .#zbook --rollback
```

## NVIDIA notes

The zbook uses NVIDIA Optimus (Intel integrated + RTX 4000 Ada) in offload
mode. These environment variables are set for wlroots compatibility:

- `WLR_NO_HARDWARE_CURSORS=1`
- `GBM_BACKEND=nvidia-drm`
- `__GLX_VENDOR_LIBRARY_NAME=nvidia`
- `LIBVA_DRIVER_NAME=nvidia`

The NVIDIA GSP firmware is disabled (`NVreg_EnableGpuFirmware=0`) to prevent
crashes on s2idle resume. See `modules/nixos/nvidia.nix` for details.

Also check the [zbook known issues](../AGENTS.md#zbook-known-issues) list for
suspend, dock, and Logitech receiver quirks.

## Resources

- [awesome-hyprland](https://github.com/hyprland-community/awesome-hyprland) — curated list of Hyprland tools, plugins, themes, and configs
- [Hyprland Wiki](https://wiki.hyprland.org) — official documentation
- [Hyprland Community](https://github.com/hyprland-community) — community-maintained tools and bindings
- [Hyprland plugin API](https://github.com/hyprwm/hyprland-plugins) — official plugins repo
- [nixpkgs Hyprland section](https://search.nixos.org/packages?channel=unstable&query=hypr) — available Hyprland packages
- [Catppuccin Hyprland](https://github.com/catppuccin/hyprland) — Catppuccin themes for Hyprland ecosystem
