# Installing NixOS on zbook

This guide walks through installing NixOS on the HP ZBook Studio 16" G10
as the sole operating system, replacing the existing dual-boot (Windows + Ubuntu).

## Prerequisites

- A NixOS 25.05+ live ISO (tested with 25.05 "Stoat")
- This repo cloned on the live system
- The operator's SSH key (for agenix rekeying)

## Step 1: Boot the live ISO

1. Write the ISO to a USB:
   ```bash
   sudo cp nixos-plasma-x86_64-linux.iso /dev/sdX # adjust device
   ```

2. Boot from USB on the ZBook (F9 → select USB)
3. Set up networking:

   ```bash
   # WiFi
   iwctl --passphrase <pass> station wlan0 connect <ssid>
   # or USB tether / ethernet
   ```

4. Enable experimental features and clone the repo:

   ```bash
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   cd /home/nixos
   git clone https://github.com/knirski/nix-config
   cd nix-config
   nix flake check --no-build .#zbook
   ```

## Step 2: Partition and install

**WARNING: This wipes the entire NVMe drive.**

```bash
# 1. Partition, format, and mount
sudo nix run github:nix-community/disko -- --mode destroy,format,mount --flake .#zbook

# 3. Generate SSH host key (for agenix)
sudo install -d -m 700 /mnt/persist/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key

# 4. Create root-blank snapshot
sudo mount -o subvol=/ /dev/mapper/crypted /mnt
sudo btrfs subvolume snapshot -r /mnt/root /mnt/root-blank
sudo umount /mnt

# 5. Register the host public key and rekey secrets
sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub > secrets/zbook.pub
nix develop '.#' -c agenix rekey
git add secrets/zbook.pub secrets/rekeyed/
git commit -m "feat: enroll zbook agenix recipient and rekey secrets"

# 6. Install
sudo nixos-install --flake .#zbook
```

## Step 3: Post-install

```bash
# 1. Reboot
sudo reboot

# 2. Generate backup SSH key and register with backup target
sudo ssh-keygen -t ed25519 -f /persist/etc/restic/ssh-key -N "" -C "zbook-backup@zbook"
sudo cat /persist/etc/restic/ssh-key.pub
# → Register with the backup target (Synology DS423+)

# 3. Initial backup
sudo restic -r sftp:zbook-backup@czworaczki:/backup/zbook \
  -p /persist/etc/restic/password backup /persist
```

## Optional: TPM LUKS auto-unlock

After first boot, enroll a TPM keyslot:

```bash
sudo systemd-cryptenroll --tpm2-device=auto \
  --tpm2-pcrs=7 \
  /dev/disk/by-partlabel/luks
```

Test TPM unlock: `sudo systemd-cryptsetup attach crypted /dev/disk/by-partlabel/luks`

## Post-install gotchas

### NVIDIA: first boot uses nouveau

On first boot after `nixos-install`, the proprietary NVIDIA driver is **not
loaded** — nouveau (the open-source reverse-engineered driver) runs instead.
This means the COSMIC desktop will be laggy with no GPU acceleration,
because `hardware.nvidia.enabled` is read-only and only becomes `true` when
`"nvidia"` is in `services.xserver.videoDrivers`. The initial install from
the flake includes that fix, but a reboot is needed because nouveau claims
the GPU first — the NVIDIA kernel module can't hot-swap.

After first boot:

```bash
# If desktop is laggy, switch to the NVIDIA driver and reboot:
sudo nixos-rebuild switch --flake .#zbook
sudo reboot
```

After reboot, verify with `nvidia-smi`. The desktop should be smooth.

### Suspend: USB-C dock causes immediate wake

When connected to a USB-C dock (ethernet, monitor, Logitech receiver), the
laptop may wake immediately after suspend. This is fixed by udev rules that
disable ACPI wake for USB and Thunderbolt controllers — see
`modules/nixos/laptop.nix`. The rules target the specific Intel Raptor Lake
PCI IDs for this hardware, following the pattern from
[nixos-hardware PR #1394](https://github.com/NixOS/nixos-hardware/pull/1394).

If you still see immediate wake after deploy:

```bash
sudo reboot
```

A full reboot ensures the udev rules are processed at device-probe time.

## Post-install manual checks

- COSMIC desktop boots and renders correctly (after NVIDIA driver activates)
- GPU switching works (Intel integrated for desktop, NVIDIA on-demand)
- Steam launches and can render with DXVK/VKD3D
- Suspend works with USB-C dock connected (laptop stays asleep)
- Restic backup completes successfully
- TPM auto-unlock on reboot
- Tailscale connects and provides remote access
- Bluetooth, WiFi, USB-C docking work
