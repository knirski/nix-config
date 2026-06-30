# Soyo — First Install from Live USB

## Prerequisites

- NixOS 26.05 ISO with `enp1s0` support (in-tree `dwmac_motorcomm`). WiFi (`RTL8852BE`) or USB Ethernet as fallback.
- The target disk: `/dev/disk/by-id/ata-PELADN_512GB_20250522100164` (adjust in `disko.nix` if different).
- Network: live ISO gets an IP via DHCP on the LAN uplink.
- A local checkout of this repo with write access to the remote.
- Your SSH private key available on the live ISO (see [Setup SSH key](#setup-ssh-key) below).

## Setup SSH key

`agenix rekey` (step 4) needs your SSH private key to decrypt the master-encrypted
secrets. If it's already on the live ISO (e.g. you SSHed in with agent forwarding),
skip this. Otherwise copy it from your workstation:

```bash
# On Soyo's live ISO, find its IP:
ip -4 addr show | grep inet
# Look for something like "192.168.1.42/24" — that's Soyo's address.
# Then, from YOUR WORKSTATION, run:
#   scp ~/.ssh/id_ed25519 nixos@192.168.1.42:~
#   (replace id_ed25519 with your actual key file and IP)
#
# Back on Soyo's live ISO, install the key:
mkdir -p -m 700 ~/.ssh
mv ~/id_ed25519 ~/.ssh/ 2>/dev/null || echo "Key not found via scp — you can paste it manually:"
# If the mv failed, paste manually:
#   cat > ~/.ssh/id_ed25519
#   (paste the private key contents, press Ctrl+D)
chmod 600 ~/.ssh/id_ed25519
```

```bash
# Verify the key is usable:
ssh-keygen -y -f ~/.ssh/id_ed25519 > /dev/null && echo "SSH key OK"
# Expected output: "SSH key OK"
```

## 1. Clone the repo and configure git

```bash
git clone https://github.com/knirski/nix-config
cd nix-config
export NIX_CONFIG="experimental-features = nix-command flakes"
git config user.name "Your Name"
git config user.email "your@email.com"
```

```bash
# Verify:
git log --oneline -1
# Expected: some commit hash with message
```

## 2. Partition and format

Wipes the target disk and creates the LUKS + Btrfs layout from `disko.nix`:

```bash
sudo nix --extra-experimental-features 'nix-command flakes' run github:nix-community/disko -- --mode disko hosts/soyo/disko.nix
```

```bash
# Verify the mounts:
mount | grep /mnt
# Expected (5 lines):
#   /dev/mapper/crypted on /mnt (btrfs, ...)           # root
#   /dev/mapper/crypted on /mnt/nix (btrfs, ...)
#   /dev/mapper/crypted on /mnt/persist (btrfs, ...)
#   /dev/mapper/crypted on /mnt/snapshots (btrfs, ...)
#   /dev/sda1 on /mnt/boot (vfat, ...)
```

## 3. Create the blank snapshot and SSH keys

Three one-time bootstrap steps the running system depends on:

```bash
# (a) Root-blank snapshot (the initrd rollback target)
# First check if it already exists (idempotent):
if sudo btrfs subvolume list -t /mnt | grep -q root-blank; then
  echo "root-blank already exists — skipping"
else
  sudo mkdir -p /mnt-top
  sudo mount -t btrfs -o subvolid=5 /dev/mapper/crypted /mnt-top
  # Verify it's read-write
  mount | grep /mnt-top | grep -q rw || echo "WARNING: /mnt-top is read-only"
  sudo btrfs subvolume snapshot -r /mnt-top/root /mnt-top/root-blank
  sudo umount /mnt-top
fi
```

```bash
# Verify (a): root-blank snapshot exists
sudo btrfs subvolume list -t /mnt | grep root-blank
# Expected: a line containing "root-blank"
```

```bash
# (b) Soyo's initrd SSH host key (for break-glass unlock, lives on ESP)
if sudo [ -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key ]; then
  echo "initrd SSH key already exists — skipping"
else
  sudo install -d -m 700 /mnt/boot/initrd-ssh
  sudo ssh-keygen -t ed25519 -N "" -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key
fi
```

```bash
# Verify (b): initrd SSH key created
sudo ls -la /mnt/boot/initrd-ssh/
# Expected: ssh_host_ed25519_key and ssh_host_ed25519_key.pub
```

```bash
# (c) Soyo's stage-2 host key on /persist (so agenix can decrypt on first boot)
if sudo [ -f /mnt/persist/etc/ssh/ssh_host_ed25519_key ]; then
  echo "stage-2 SSH key already exists — skipping"
else
  sudo install -d -m 700 /mnt/persist/etc/ssh
  sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
fi
```

```bash
# Verify (c): stage-2 host key created
sudo ls -la /mnt/persist/etc/ssh/
# Expected: ssh_host_ed25519_key and ssh_host_ed25519_key.pub
```

## 4. Enroll Soyo and rekey secrets

Before `nixos-install`, generate host-specific rekeyed secrets from the
master-encrypted originals:

```bash
# (a) Overwrite the placeholder soyo.age.pub with the real host pubkey
sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub \
  | nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#ssh-to-age --command ssh-to-age \
  > secrets/soyo.age.pub
```

```bash
# Verify (a): soyo.age.pub now contains the real key (not the dummy)
head -1 secrets/soyo.age.pub | grep -v "age1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs3290gq" \
  && echo "Real key installed" || echo "ERROR: still the dummy key!"
# Expected: "Real key installed"
```

```bash
# (b) Rekey all secrets for Soyo — decrypts with your master identity (SSH key)
#     and re-encrypts with Soyo's host key. Results go to secrets/rekeyed/soyo/.
#
# NOTE: First `nix develop` builds the devshell from scratch — may take a few
#       minutes. If rage prompts for your SSH key passphrase, enter it.
#       NIX_CONFIG propagates experimental features to agenix-rekey's internal nix calls.
NIX_CONFIG="experimental-features = nix-command flakes" NIX_CONFIG="experimental-features = nix-command flakes" nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey
```

```bash
# Verify (b): rekeyed secrets exist
ls -la secrets/rekeyed/soyo/
# Expected: 4 .age files (root-password, krzysiek-password, restic-password, ntfy-token)
```

```bash
# (c) Commit the new host pubkey and rekeyed secrets
git add secrets/soyo.age.pub secrets/rekeyed/
git commit -m "feat: enroll soyo agenix recipient and rekey secrets"
git push || echo "Push skipped (HTTPS auth) — push from your workstation later."
```

```bash
# Verify (c): committed
git log --oneline -1
# Expected: "feat: enroll soyo agenix recipient and rekey secrets"
```

## 5. Install

```bash
sudo NIX_CONFIG="$NIX_CONFIG" nixos-install --flake .#soyo
```

```bash
# Verify: build succeeded (nixos-install exits 0 on success)
echo "Exit code: $?"
# If 0, proceed to reboot. If non-zero, scroll up and check the error.
```

Reboot Soyo. After reboot, TPM should auto-unlock, LAN DHCP/DNS should be
running, and all secrets decrypted.

> **Cleanup:** If you copied your SSH private key onto the live ISO (`id_ed25519`),
> remove it before discarding the USB:
> `rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub`

## 6. Enroll TPM (if not auto-detected)

If the TPM was not automatically enrolled during install:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/luks
```

```bash
# Verify TPM enrollment
sudo systemd-cryptenroll /dev/disk/by-partlabel/luks | grep -i tpm
# Expected: a line mentioning "TPM2" or the PCR binding
```

## 7. Validate

```bash
# Kernel is linuxPackages_latest
uname -r

# NIC driver is in-tree dwmac_motorcomm
ethtool -i enp1s0 | grep driver
# Expected: driver: dwmac_motorcomm

# DNS resolves (Blocky on :53)
dig +short soyo.home.arpa @127.0.0.1

# DHCP issues leases
journalctl -u dnsmasq -n 5 --no-pager

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
NIX_CONFIG="experimental-features = nix-command flakes" nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey
```

## Changing a password

```bash
# 1. Generate a new SHA-512 password hash
mkpasswd -m sha-512

# 2. Edit the master-encrypted secret (uses your master identity — SSH key)
NIX_CONFIG="experimental-features = nix-command flakes" nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix edit secrets/root-password.age

# 3. Rekey so the change propagates to the host-specific rekeyed secret
NIX_CONFIG="experimental-features = nix-command flakes" nix --extra-experimental-features 'nix-command flakes' develop '.#' -c agenix rekey

# 4. Commit and deploy
git add secrets/root-password.age secrets/rekeyed/
git commit -m "chore: update root password"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

Same flow for `krzysiek-password.age` or any other secret.

## Recovery paths

See the recovery runbook at `docs/recovery.md` (not yet written) or the
[design doc](../docs/superpowers/specs/soyo-dns-dhcp-appliance.md) for TPM,
remote initrd SSH, and direct-link rescue procedures.
