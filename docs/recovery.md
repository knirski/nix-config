# Recovery

Consolidated runbook for every failure mode. Start here when Soyo is down.

> **Hostname vs IP:** All examples use `soyo` (resolved via Blocky's `customDNS`
> from `reservations.nix`). If DNS is the problem you're troubleshooting, fall
> back to the static IP: `krzysiek@10.0.0.9` for SSH, `10.0.0.9:3000` for
> Grafana, etc.

## Enable Tailscale

Tailscale is pre-installed and configured on Soyo. After the first deploy, it
authenticates automatically using the encrypted auth key. Once connected, you
can reach Soyo from anywhere without open ports or DynDNS:

```sh
ssh krzysiek@soyo
```

To verify or check status:

```sh
ssh krzysiek@soyo
tailscale status
```

If Tailscale isn't connected (e.g. after a full reinstall), force a re-auth:

```sh
sudo tailscale logout
# The auto-auth service will re-authenticate on next boot,
# or run manually:
sudo tailscale up --auth-key "$(cat /run/agenix/tailscale-auth-key)"
```

## Normal power loss

Nothing to do. Soyo powers on (BIOS "State After G3" = S0), TPM auto-unlocks the disk, and DNS/DHCP resume in about a minute. Confirm with the Synology Uptime Kuma probe.

If Soyo doesn't power on: BIOS AC-power-recovery setting may have reset. Enter BIOS and set "State After G3" to S0.

## TPM auto-unlock failed (PCR change, cleared TPM)

The passphrase keyslot is always kept as fallback. Three ways in:

### 1. Local console

Plug in a keyboard and monitor. Enter the LUKS passphrase at the prompt.

### 2. LAN initrd SSH

From a machine on the LAN:

```sh
ssh -p 2222 root@soyo
```

If SSH lands at an initrd shell prompt such as `-bash-5.3#`, start the systemd password agent manually:

```sh
systemd-tty-ask-password-agent --watch
```

Then enter the LUKS passphrase at the prompt. The initrd SSH host key fingerprint should be stable across rebuilds (it lives on the ESP at `/boot/initrd-ssh/`). If the fingerprint changed: a fresh install or ESP reformat regenerated it — accept the new key on first use.

### 3. Direct-link rescue

When the LAN/router is down **and** the box is headless:

1. Connect a laptop directly to Soyo's Ethernet port (remove the cable from the switch/router).
2. Configure the laptop with a static IP in the rescue subnet:

   ```sh
   sudo ip addr add 192.168.254.1/30 dev eth0
   sudo ip link set eth0 up
   ```

3. SSH to the rescue address:

   ```sh
   ssh -p 2222 root@192.168.254.2
   ```

4. If SSH lands at an initrd shell prompt such as `-bash-5.3#`, run:

   ```sh
   systemd-tty-ask-password-agent --watch
   ```

5. Enter the LUKS passphrase.
6. After boot, reconnect Soyo to the LAN switch/router.

### After successful unlock (Phase 2 — Secure Boot)

If the cause was a PCR change (kernel/initrd/bootloader update), re-enroll against PCR 0+2+7:

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks
```

If `--wipe-slot=tpm2` prints `No slots to remove selected.`, there was no TPM slot enrolled yet. Continue with the enroll command.

## Phase 2 — Limine Secure Boot setup (one-time operator steps)

These steps enable Secure Boot with custom keys on Soyo. Run once after deploying the Phase 2 config.

### Prerequisites

- Soyo has `boot.loader.limine.secureBoot.enable = true` in the deployed config (the nixpkgs module force-enables `enrollConfig`, `validateChecksums`, and `panicOnChecksumMismatch`; the editor is locked).
- Firmware Secure Boot Mode can be switched to **Customized** (confirmed available on this board).
- `sbctl` is available on Soyo. If you are cutting over from an older generation that does not ship it system-wide yet, run the `sbctl` commands below via `nix shell nixpkgs#sbctl -c ...`.

### Steps

```sh
# 1. Put firmware into Setup Mode — boot into BIOS, set Secure Boot Mode to
#    Customized, then use "Reset to Setup Mode" to clear the factory keys.
#    Reboot.

# 2. Generate custom Secure Boot keys on Soyo.
sudo sbctl create-keys

# 3. Enroll keys, keeping Microsoft keys so option ROMs and vendor firmware still load.
sudo sbctl enroll-keys -m

# 4. From your workstation, deploy once more before the next reboot.
#    This signs Limine with the newly-created keys and persists /var/lib/sbctl
#    on the impermanent root so future bootloader installs keep working.
nix develop '.#' -c deploy .#soyo

# 5. Enable Secure Boot in firmware.
#    BIOS → Secure Boot → Enabled. If "Reset to Setup Mode" is still active,
#    toggle it off first.

# 6. Re-enroll the TPM keyslot against PCR 0+2+7 for firmware+tamper coverage.
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks

# 7. Verify.
sudo sbctl status
# Expected: Setup Mode: User, Secure Boot: enabled.
```

`sbctl status` may still show `Installed: ✗ sbctl is not installed` in this setup. That field is about sbctl's own tracked-file database, while the NixOS Limine module signs `BOOTX64.EFI` directly during activation.

### Recovery if Secure Boot blocks boot

If Secure Boot prevents booting during setup (wrong keys, unsigned image):

1. Enter BIOS, set Secure Boot back to **Standard** (or disable it).
2. Boot normally — the passphrase keyslot is an independent fallback throughout.
3. If the failed deploy complained that there were no `sbctl` Secure Boot keys, return firmware to Setup Mode, recreate the keys, deploy once before rebooting again, then re-enable Secure Boot.

### Zbook

Zbook uses the same Secure Boot mechanism (Limine + `sbctl`), but the operator steps differ slightly because it is a laptop with HP firmware.

The same caveats about `/var/lib/sbctl` persistence and `fwupd` apply.

#### Zbook prerequisites

- Zbook has `boot.loader.limine.secureBoot.enable = true` in the deployed config.
- HP firmware Secure Boot can be toggled in BIOS → Security → Secure Boot Configuration.
- `sbctl` is available on zbook (same as on Soyo).

#### Zbook steps

```sh
# 1. Reboot into BIOS and put firmware into Setup Mode.
#    HP ZBook BIOS → Security → Secure Boot Configuration → Advanced.
#    Set Secure Boot to "Disabled" under Advanced, then select "Clear All
#    Secure Boot Keys" under Key Management to erase factory keys.
#    Apply, reboot.

# 2. Generate custom Secure Boot keys on zbook.
sudo sbctl create-keys

# 3. Enroll keys, keeping Microsoft keys so option ROMs still load.
sudo sbctl enroll-keys -m

# 4. From your workstation, deploy once more before the next reboot.
#    This signs Limine with the newly-created keys and persists /var/lib/sbctl.
nix develop '.#' -c deploy .#zbook

# 5. Enable Secure Boot in firmware.
#    ZBook BIOS → Security → Secure Boot Configuration → Enable Secure Boot.
#    Set to "Enabled" (not "Legacy" or "Audit").

# 6. Re-enroll the TPM keyslot against PCR 0+2+7.
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks

# 7. Verify.
sudo sbctl status
# Expected: Setup Mode: User, Secure Boot: enabled.
```

If HP firmware does not expose a "Setup Mode" toggle (some ZBook BIOS revisions hide it), you can trigger Setup Mode from Linux with `mokutil` or by enrolling `sbctl` platform-owner keys. If the above fails:

```sh
# Alternative: trigger Setup Mode from Linux with sbctl
sudo sbctl enroll-keys -m --force
```

If the BIOS shows "Secure Boot → Audit Mode" instead of "Enabled" after enrollment, the keys were accepted but the BIOS is not enforcing. Check with `sudo sbctl status` — if Secure Boot shows `enabled`, it is enforced regardless of the BIOS label.

### Caveats

- `fwupd` is currently broken under Limine Secure Boot ([nixpkgs #534574](https://github.com/NixOS/nixpkgs/issues/534574)). LVFS firmware updates may need Secure Boot temporarily off.
- PCR 0+2+7 is stable across kernel/initrd/bootloader updates — auto-unlock survives normal deployments without re-enrollment. Only a BIOS/firmware update (changes PCR 0) or clearing the TPM requires re-enrollment.
- On an impermanent root, `/var/lib/sbctl` is real persistent state. If that directory is lost, the current signed boot path can still boot, but the next Limine reinstall fails with `There are no sbctl secure boot keys present. Please generate some.`

## Soyo fully down (dead hardware, no power)

1. Procure a replacement (same model, or any x86_64 box).
2. Boot the NixOS 26.05 installer USB.
3. Follow [`docs/install-soyo.md`](install-soyo.md) — the full provisioning flow.
4. After install, restore class 3 data from the Synology:

   ```sh
   sudo restic -r sftp:soyo-backup@nas.home.arpa:/backup/soyo \
     -p $(cat /run/agenix/restic-password) restore latest --target /
   ```

5. Re-enroll agenix: new host has a new SSH host key. Generate it, save the pubkey to `secrets/soyo.pub`, run `agenix rekey`, commit the rekeyed files, deploy.

6. On the Synology: update Uptime Kuma to probe the new host if the IP changed.

## NIC failure (enp1s0 dead)

The onboard `yt6801` is a single port. If it fails:

1. Use onboard WiFi (`RTL8852BE`, in-tree) for emergency SSH access to diagnose.
2. For restoring service: plug in a known-working USB Ethernet adapter. Update `hosts/soyo/networking.nix` with the new interface name, then deploy.

## Disk full / near-full

Low disk space can break the appliance (no leases, no rebuild). Btrfs has a caveat: `df` is misleading — use `btrfs filesystem usage` instead.

```sh
btrfs filesystem usage /
```

If near-full:

```sh
# Drop old snapshots first (quickest win)
sudo btrbk -c /etc/btrbk/soyo.conf dryrun  # see what would be removed
sudo btrbk -c /etc/btrbk/soyo.conf run

# Delete old Nix generations
sudo nix-collect-garbage --delete-older-than 7d
sudo nixos-rebuild boot  # clean up the boot entries too

# If metadata is exhausted (free space but ENOSPC):
sudo btrfs balance start -musage=5 /
```

## SMART warning

`smartd` sends an ntfy notification on disk errors. When you get one:

```sh
sudo smartctl -a /dev/disk/by-id/ata-PELADN_512GB_20250522100164
```

1. Verify the latest restic backup is restorable (see [backup-and-restore.md](./backup-and-restore.md)).
2. Order a replacement SSD.
3. The disk is on borrowed time. With no RAID, there's no limp mode — treat this as urgent.

## Operator machine lacks DHCP during recovery

If your laptop needs an IP but Soyo's DHCP is down:

```sh
sudo ip addr add 10.0.0.100/24 dev eth0
sudo ip route add default via 10.0.0.1
```

This gives a static IP in the normal LAN range so you can reach Soyo by IP.

## Restore from scratch (full disk replacement)

Reuses the provisioning flow with an extra restore step:

1. Provision via [`docs/install-soyo.md`](install-soyo.md) with `disko` from the flake.
2. Restore class 3 data: `sudo restic -r sftp:soyo-backup@nas.home.arpa:/backup/soyo -p /run/agenix/restic-password restore latest --target /`
3. Re-enroll agenix with the new host key.
4. Update `hosts/soyo/facter.json` if the replacement hardware differs.
5. Re-enroll TPM against PCR 0+2+7: `sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks`
