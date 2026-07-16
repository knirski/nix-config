# Troubleshooting Guide

Common issues and solutions for the zbook workstation.

## NVIDIA Issues

### First Boot: Nouveau Instead of NVIDIA

**Symptom**: After first install, `lspci -k` shows `nouveau` driver instead of `nvidia`.

**Cause**: Nouveau claims the GPU first; kernel modules can't hot-swap.

**Solution**:
```bash
nixos-rebuild switch --flake .#zbook
sudo reboot
```

### NVIDIA GSP Firmware Crash (Xid 120) on s2idle Resume

**Symptom**: After waking from suspend, NVIDIA GPU is wedged with "Input/output error" in `/proc/driver/nvidia/suspend`.

**Cause**: GSP RISC-V firmware panic on first s2idle resume.

**Solution**: Already fixed via `NVreg_EnableGpuFirmware=0` in `modules/nixos/nvidia.nix`. Requires cold boot to apply.

### Games Not Using NVIDIA GPU

**Symptom**: Games run with poor performance on integrated GPU.

**Cause**: NVIDIA offload not configured for application.

**Solution**: Environment variables are set for Steam and Heroic Launcher. For other applications:
```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia ./your-game
```

## Suspend Issues

### No Deep S3 Sleep

**Symptom**: System uses s2idle instead of deep sleep.

**Cause**: HP firmware configured for S0ix-native wake; S3 wake events not routed.

**Solution**: This is expected. s2idle is used. If immediate wake happens after suspend, check USB dock Ethernet:
```bash
# Check wake sources
sudo journalctl -b | grep -i wake
```

### NetworkManager "Connected" But No Internet After Resume

**Symptom**: Network shows connected but no internet access after waking from suspend.

**Cause**: USB-C dock Ethernet data path broken after s2idle resume.

**Solution**: Already fixed via `powerManagement.resumeCommands` in `modules/nixos/laptop.nix` which restarts NetworkManager on resume.

**Manual fix**:
```bash
sudo systemctl restart NetworkManager
```

## Input Devices

### Logitech Receiver Stutter

**Symptom**: Keyboard/mouse disconnects periodically.

**Cause**: Powertop's `--auto-tune` suspends the Unifying/Bolt receiver.

**Solution**: Already fixed via `usbcore.quirks` kernel parameter in `modules/nixos/laptop.nix`. Requires reboot after parameter change.

### Touchpad Not Working

**Symptom**: Touchpad doesn't respond to taps.

**Cause**: Touchpad configuration not applied.

**Solution**: Check Sway input configuration:
```bash
swaymsg -t get_inputs
```

Ensure tap is enabled:
```bash
swaymsg input type:touchpad tap enabled
```

## Audio

### No Sound

**Symptom**: Audio doesn't work.

**Cause**: PipeWire not running or wrong output device.

**Solution**:
```bash
# Check PipeWire status
systemctl --user status pipewire pipewire-pulse wireplumber

# Restart PipeWire
systemctl --user restart pipewire pipewire-pulse wireplumber

# List audio devices
pactl list sinks short
```

### Audio Stops Playing After Idle

**Symptom**: Audio stops after 10 minutes of keyboard/mouse idle.

**Cause**: DMS's `acSuspendTimeout` fires regardless of audio playback.

**Solution**: Already fixed via `media-sleep-inhibit` systemd user service in `modules/home/sway.nix`.

## Display

### Sway Won't Start

**Symptom**: Sway fails to start with "unsupported GPU" error.

**Cause**: NVIDIA GPU not officially supported by Sway.

**Solution**: Already fixed via `SWAY_UNSUPPORTED_GPU=1` in `modules/nixos/sway.nix`.

### Screen Tearing

**Symptom**: Visual tearing during video playback or scrolling.

**Cause**: VSync not enabled.

**Solution**: Check Sway config:
```bash
swaymsg -t get_outputs
```

Ensure VSync is enabled in Sway config.

### Display Not Detected

**Symptom**: External monitor not detected.

**Cause**: Display configuration issue.

**Solution**:
```bash
# List outputs
swaymsg -t get_outputs

# Enable output
swaymsg output <name> enable

# Use nwg-displays for GUI configuration
nwg-displays
```

## Docker/Podman

### Docker Data Lost on Reboot

**Symptom**: All Docker images and containers disappear after reboot.

**Cause**: `/var/lib/docker` not persisted (ephemeral root).

**Solution**: Already fixed by switching to Podman. Podman stores data in `~/.local/share/containers` which is persisted.

**If using Docker**:
```bash
# Add to persistence
sudo mkdir -p /persist/var/lib/docker
sudo ln -s /persist/var/lib/docker /var/lib/docker
```

### Podman Commands Not Working

**Symptom**: `docker` commands fail.

**Cause**: Podman compatibility layer not configured.

**Solution**: Already fixed via `virtualisation.podman.dockerCompat = true`.

## Nix

### Build Fails with "hash mismatch"

**Symptom**: Nix build fails with hash mismatch error.

**Cause**: Flake lock file out of date.

**Solution**:
```bash
nix flake update
just deploy zbook
```

### "Too many open files" Error

**Symptom**: Nix build fails with "too many open files".

**Cause**: System file descriptor limit too low.

**Solution**:
```bash
# Check current limit
ulimit -n

# Increase limit temporarily
ulimit -n 65536

# Or add to configuration.nix
# security.pam.loginLimits = [{ domain = "*"; type = "-"; item = "nofile"; value = "65536"; }];
```

### nix-locate Takes Forever

**Symptom**: `nix-locate` takes hours to build index.

**Cause**: Using standalone nix-index without pre-built database.

**Solution**: Already fixed via `nix-index-database` which provides weekly pre-built database.

## Backups

### Restic Backup Fails

**Symptom**: Backup job fails.

**Cause**: NAS not reachable or credentials wrong.

**Solution**:
```bash
# Check NAS connectivity
ping czworaczki.home.arpa

# Check backup logs
journalctl -u restic-backups-persist.service

# Run backup manually
sudo systemctl start restic-backups-persist.service
```

### Btrbk Snapshot Space

**Symptom**: Disk space low.

**Cause**: Too many Btrfs snapshots.

**Solution**:
```bash
# List snapshots
sudo btrfs subvolume list /

# Delete old snapshots
sudo btrfs subvolume delete /.snapshots/*-*

# Or let btrbk prune automatically
sudo btrbk prune
```

## Polkit

### GUI Elevation Requests Hang

**Symptom**: GUI apps that request elevated privileges hang.

**Cause**: Polkit agent not running.

**Solution**: Already fixed via `polkit-gnome-authentication-agent` systemd user service.

**Manual fix**:
```bash
systemctl --user start polkit-gnome-authentication-agent
```

## SSH

### SSH Agent Not Working

**Symptom**: SSH keys not loaded into agent.

**Cause**: SSH agent not running or keys not added.

**Solution**:
```bash
# Check if agent is running
ssh-add -l

# Add keys
ssh-add ~/.ssh/id_ed25519

# Or restart agent
eval "$(ssh-agent -s)"
ssh-add
```

### SSH Multiplexing Not Working

**Symptom**: New SSH connections don't reuse existing connections.

**Cause**: Socket directory not created.

**Solution**:
```bash
mkdir -p ~/.ssh/sockets
```

## Wayland/XDG

### Screen Sharing Not Working

**Symptom**: Screen sharing in Firefox/Electron apps doesn't work.

**Cause**: XDG desktop portal not configured.

**Solution**: Already fixed via `xdg-desktop-portal-wlr` and `xdg-desktop-portal-gtk`.

**Manual fix**:
```bash
# Check portal status
systemctl --user status xdg-desktop-portal xdg-desktop-portal-wlr
```

### File Picker Not Working

**Symptom**: File dialogs don't open or hang.

**Cause**: XDG portal not configured.

**Solution**: Already fixed. If still issues:
```bash
# Set environment variable
export GTK_USE_PORTAL=1
```

## Fonts

### Fonts Look Blurry

**Symptom**: Fonts appear blurry or aliased.

**Cause**: Font rendering not configured.

**Solution**: Check font configuration:
```bash
# List installed fonts
fc-list | grep -i "inter\|fira\|jetbrains"

# Rebuild font cache
fc-cache -fv
```

### DMS Shows Wrong Font

**Symptom**: DMS uses fallback font instead of Inter Variable.

**Cause**: Inter Variable not installed.

**Solution**: Already fixed via `pkgs.inter` in `modules/nixos/desktop.nix`.

## Gaming

### Steam Won't Launch

**Symptom**: Steam fails to start.

**Cause**: Missing 32-bit libraries or NVIDIA driver issue.

**Solution**:
```bash
# Check NVIDIA driver
nvidia-smi

# Restart Steam
steam --reset

# Check logs
journalctl -u steam
```

### Games Crash on Startup

**Symptom**: Games crash immediately on launch.

**Cause**: Missing Proton version or compatibility issue.

**Solution**:
```bash
# Install Proton GE
protonup-qt

# Or use specific Proton version
# In Steam: Right-click game → Properties → Compatibility → Force Proton version
```

### Low FPS in Games

**Symptom**: Games run with low FPS.

**Cause**: Game not using NVIDIA GPU.

**Solution**: Check if NVIDIA offload is working:
```bash
# Check GPU usage
nvidia-smi

# For Steam games, add to launch options:
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia %command%
```

## Getting Help

### Check System Logs

```bash
# System logs
journalctl -b -1  # Previous boot
journalctl -u <service>  # Specific service

# NixOS build logs
nixos-rebuild switch --flake .#zbook 2>&1 | tee build.log
```

### Run Healthcheck

```bash
just healthcheck zbook
```

### Check Configuration

```bash
# Verify Nix files parse correctly
nix-instantiate --parse <file>.nix

# Check for syntax errors
nix flake check
```

### Useful Commands

```bash
# System information
fastfetch

# Disk usage
duf

# Process monitor
btop

# Network connections
ss -tulnp

# System services
systemctl list-units --type=service
```
