# Soyo — First Install from Live USB

## Prerequisites

- NixOS 26.05 ISO with `enp1s0` support (in-tree `dwmac_motorcomm`). WiFi (`RTL8852BE`) or USB Ethernet as fallback.
- The target disk: `/dev/disk/by-id/ata-PELADN_512GB_20250522100164` (adjust in `disko.nix` if different).
- Network: live ISO gets an IP via DHCP on the LAN uplink.
- A local checkout of this repo with write access to the remote.
- Your SSH private key (the one corresponding to `secrets/krzysiek.age.pub`) to decrypt master-encrypted secrets.

## 1. Boot the live ISO and clone

```bash
# Optional: bring up WiFi if wired is down
# iwctl station wlan0 connect <SSID>

# Clone the config and enable flakes
git clone https://github.com/knirski/nix-config
cd nix-config
export NIX_CONFIG="experimental-features = nix-command flakes"
```

## 2. Partition and format

Wipes the target disk and creates the LUKS + Btrfs layout from `disko.nix`:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko -- --mode disko hosts/soyo/disko.nix
```

`/mnt` is now mounted with `root` at `/mnt`, `nix` at `/mnt/nix`, `persist` at `/mnt/persist`, and `/boot` at `/mnt/boot`.

## 3. Create the blank snapshot and SSH keys

Three one-time bootstrap steps the running system depends on:

```bash
# (a) Root-blank snapshot (the initrd rollback target)
sudo mkdir -p /mnt-top
sudo mount -o subvol=/ /dev/mapper/crypted /mnt-top
sudo btrfs subvolume snapshot -r /mnt-top/root /mnt-top/root-blank
sudo umount /mnt-top

# (b) Soyo's initrd SSH host key (for break-glass unlock, lives on ESP)
sudo install -d -m 700 /mnt/boot/initrd-ssh
sudo ssh-keygen -t ed25519 -N "" -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key

# (c) Soyo's stage-2 host key on /persist (so agenix can decrypt on first boot)
sudo install -d -m 700 /mnt/persist/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

These are the **machine's** host keys, not your personal SSH key. Your own key is
needed in step 4 to decrypt the master-encrypted secrets during `agenix rekey`.

## 4. Enroll Soyo and rekey secrets

Before `nixos-install`, generate host-specific rekeyed secrets from the
master-encrypted originals:

```bash
# (a) Derive the age public key from the stage-2 host key
#     (the pubkey was created by sudo in step 3 — pipe it through sudo cat)
sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub \
  | nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age --command ssh-to-age \
  > secrets/soyo.age.pub

# (b) Set hostPubkey in the assembler so agenix-rekey encrypts for the real host key
#     Edit modules/parts/soyo.nix — uncomment or set:
#       hostPubkey = ../../secrets/soyo.age.pub;

# (c) Rekey all secrets for Soyo — decrypts with your master identity (SSH key)
#     and re-encrypts with Soyo's host key. Results go to secrets/rekeyed/soyo/.
#
# NOTE: This needs your SSH private key. Copy it first if not present:
#   install -d -m 700 ~/.ssh && cat > ~/.ssh/id_ed25519
#   (paste the key, then Ctrl+D; or use scp/ssh-agent)
nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey

# (d) Commit the new host pubkey and rekeyed secrets, push
git add secrets/soyo.age.pub secrets/rekeyed/
git commit -m "feat: enroll soyo agenix recipient and rekey secrets"
git push
```

## 5. Install

```bash
sudo NIX_CONFIG="$NIX_CONFIG" nixos-install --flake .#soyo
```

Reboot. Soyo comes up with TPM auto-unlock, LAN DHCP/DNS, and all secrets decrypted.

## 6. Enroll TPM (if not auto-detected)

If `boot.initrd.luks.devices.crypted.crypttabExtraOpts` doesn't auto-enroll, run on the target:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/luks
```

Phase 2 (M3) will bind PCR 0+2+7 with Secure Boot.

## 7. Validate

```bash
# Kernel is linuxPackages_latest
uname -r

# NIC driver is in-tree dwmac_motorcomm
ethtool -i enp1s0

# DNS resolves (Blocky on :53)
dig +short soyo.home.arpa @127.0.0.1

# DHCP issues leases
journalctl -u dnsmasq -n 20

# TPM unlock works
sudo journalctl -u systemd-cryptsetup@crypted --no-pager | tail
```

## Subsequent deploys

From a workstation on the LAN:

```bash
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

Or locally on Soyo:

```bash
sudo nixos-rebuild switch --flake .#soyo
```

When secrets change, re-run `agenix rekey` on the build workstation before deploying:

```bash
nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey
```

## Changing a password

```bash
# 1. Generate a new SHA-512 password hash
mkpasswd -m sha-512

# 2. Edit the master-encrypted secret (uses your master identity — SSH key)
nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix edit secrets/root-password.age

# 3. Rekey so the change propagates to the host-specific rekeyed secret
nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/root-password.age secrets/rekeyed/
git commit -m "chore: update root password"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

Same flow for `krzysiek-password.age` or any other secret.

## Recovery paths

See the recovery runbook at `docs/recovery.md` (not yet written) or the [design doc](../docs/superpowers/specs/soyo-dns-dhcp-appliance.md) for TPM, remote initrd SSH, and direct-link rescue procedures.
