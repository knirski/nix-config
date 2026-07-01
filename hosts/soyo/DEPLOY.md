# Soyo — First Install from Live USB

## Prerequisites

- NixOS 26.05 ISO with `enp1s0` support (in-tree `dwmac_motorcomm`). WiFi (`RTL8852BE`) or USB Ethernet as fallback.
- The target disk: `/dev/disk/by-id/ata-PELADN_512GB_20250522100164` (adjust in `disko.nix` if different).
- Network: live ISO gets an IP via DHCP on the LAN uplink.
- A local checkout of this repo with write access to the remote.
- A GitHub personal access token (classic, with `repo` scope) for `gh` CLI auth.
- Your SSH private key on the live ISO for `agenix rekey` (see below).

## Setup SSH key (for agenix rekey)

This key is **only needed for `agenix rekey`** to decrypt master-encrypted secrets.
Git operations use `gh` instead (see below). If your SSH key is already on the live
ISO (e.g. you SSHed in with agent forwarding), skip this.

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
# Verify the key is usable: rage can parse SSH keys natively, so
# this works even if the live ISO's libcrypto is too new for ssh-keygen.
# (The `2>/dev/null` suppresses the identity file header in output.)
echo "test" | nix run nixpkgs#rage -- -e -i ~/.ssh/id_ed25519 -o /tmp/.age-test 2>/dev/null \
  && nix run nixpkgs#rage -- -d -i ~/.ssh/id_ed25519 /tmp/.age-test 2>/dev/null | grep -q test \
  && echo "SSH key OK" && rm -f /tmp/.age-test
# Expected output: "SSH key OK"
```

## Setup gh CLI (for git auth)

`gh` handles all GitHub auth (clone, push) without fuss. Install and log in:

```bash
nix profile install nixpkgs#gh
gh auth login
# Follow the prompts:
#   1. GitHub.com (default)
#   2. HTTPS (recommended) or SSH
#   3. Login with a browser — copy the one-time code, open
#      https://github.com/login/device on any machine, paste it.
#      Or paste an authentication token (classic, repo scope).
```

```bash
# Verify:
gh auth status
# Expected: "Logged in to github.com as <your-username>"
```

## 1. Clone the repo and configure git

```bash
gh repo clone knirski/nix-config
cd nix-config

# Enable experimental features permanently so every nix command
# works without --extra-experimental-features:
mkdir -p ~/.config/nix
grep -qxF "experimental-features = nix-command flakes" ~/.config/nix/nix.conf 2>/dev/null \
  || echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

```bash
# Verify:
git log --oneline -1
# Expected: some commit hash with message
```

## 2. Partition and format

Wipes the target disk and creates the LUKS + Btrfs layout from `disko.nix`:

```bash
sudo nix run github:nix-community/disko -- --mode disko hosts/soyo/disko.nix
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
master-encrypted originals.  The config points `masterIdentities` to
`/home/nixos/.ssh/id_ed25519` — your key from step 1 lives at that path,
so decryption works.

```bash
# (a) Overwrite the placeholder soyo.pub with the real host SSH pubkey.
#     Go `age` (used by agenix activation on the target) requires raw SSH
#     public keys (not X25519 age pubkeys) to match with `-i ssh_key`.
sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub \
  > secrets/soyo.pub
```

```bash
# Verify (a): soyo.pub now contains the real key (not the dummy)
head -1 secrets/soyo.pub | grep -q ssh-ed25519 \
  && echo "Real key installed" || echo "ERROR: not an SSH public key!"
# Expected: "Real key installed"
```

```bash
# (b) Rekey all secrets for Soyo — decrypts with your master identity (SSH key)
#     and re-encrypts with Soyo's host key. Results go to secrets/rekeyed/soyo/.
#
# NOTE: First `nix develop` builds the devshell from scratch — may take a
#       few minutes. If rage prompts for your SSH key passphrase, enter it.
nix develop '.#' -c agenix rekey
```

```bash
# Verify (b): rekeyed secrets exist
ls -la secrets/rekeyed/soyo/
# Expected: 4 .age files (root-password, krzysiek-password, restic-password, ntfy-token)
```

```bash
# (c) Commit the new host pubkey and rekeyed secrets
git add secrets/soyo.pub secrets/rekeyed/
git commit -m "feat: enroll soyo agenix recipient and rekey secrets"
git push
```

```bash
# Verify (c): committed
git log --oneline -1
# Expected: "feat: enroll soyo agenix recipient and rekey secrets"
```

## 5. Install

```bash
sudo nixos-install --flake .#soyo
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

> **Post-deploy:** Update `masterIdentities` in `modules/parts/soyo.nix` to
> your workstation's SSH key path (e.g. `/home/krzysiek/.ssh/id_ed25519`)
> before running `agenix rekey` from your workstation later.

## Subsequent deploys

> **Prerequisite:** The base NixOS module (`modules/nixos/base.nix`) sets
> `nix.settings.trusted-users` to include `krzysiek` and `@wheel`, and
> `modules/nixos/users.nix` sets `wheelNeedsPassword = false`. Without these,
> `nixos-rebuild --target-host` fails because the remote nix daemon rejects
> unsigned store paths and sudo requires a TTY for password prompts.
>
> **First deploy after `nixos-install`:** The freshly installed system runs
> the M1 config, which may not yet have `trusted-users` or passwordless sudo
> if these were added later in development. The first `--target-host` deploy
> from a workstation will fail for this reason. Bootstrap by building locally
> on Soyo once:
>
> ```bash
> # On Soyo (cloned repo or pulled from GitHub):
> git pull
> sudo nixos-rebuild switch --flake .#soyo
> ```
>
> After that activation completes, remote deploys from a workstation work.

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
nix develop '.#' -c agenix rekey
```

## Changing a password

```bash
# 1. Generate a new SHA-512 password hash
mkpasswd -m sha-512

# 2. Edit the master-encrypted secret (uses your master identity — SSH key)
nix develop '.#' -c agenix edit secrets/root-password.age

# 3. Rekey so the change propagates to the host-specific rekeyed secret
nix develop '.#' -c agenix rekey

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
