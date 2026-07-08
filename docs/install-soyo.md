# Soyo — First Install from Live USB

This guide walks through provisioning Soyo from a NixOS live USB: partition,
encrypt, bootstrap secrets, install, and validate. It is the companion to
[`hosts/soyo/DEPLOY.md`](../hosts/soyo/DEPLOY.md), which holds the condensed
checklist; this doc explains *why* each step exists.

> **If installing on replacement hardware:** run `nixos-facter` first to
> generate the hardware report, commit it as `hosts/<name>/facter.json`, then
> follow the same pattern.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Step 1: Boot the live ISO](#step-1-boot-the-live-iso)
- [Step 2: Set up SSH key and GitHub auth](#step-2-set-up-ssh-key-and-github-auth)
- [Step 3: Clone the repo](#step-3-clone-the-repo)
- [Step 4: Partition and format (disko)](#step-4-partition-and-format-disko)
- [Step 5: One-time bootstrap steps](#step-5-one-time-bootstrap-steps)
- [Step 6: Enroll Soyo in agenix and rekey secrets](#step-6-enroll-soyo-in-agenix-and-rekey-secrets)
- [Step 7: Install](#step-7-install)
- [Step 8: Post-install enrollment](#step-8-post-install-enrollment)
- [Step 9: Validate](#step-9-validate)
- [Subsequent deploys](#subsequent-deploys)

---

## Prerequisites

- A **NixOS 26.05 ISO** (or later). The live environment's kernel must have
  the in-tree `dwmac_motorcomm` driver so `enp1s0` comes up. The 26.05 ISO
  ships with `linuxPackages_latest`, which includes it.

- The target disk is identified by-id:
  `/dev/disk/by-id/ata-PELADN_512GB_20250522100164`. If the disk differs,
  update `hosts/soyo/disko.nix` before running disko.

- **Fallback connectivity:** If the wired NIC does not come up (kernel
  regression, different ISO), use onboard WiFi (`RTL8852BE`, in-tree
  `rtw89_8852be` driver on `wlp2s0`) or a USB Ethernet adapter.

- A **GitHub personal access token** (classic, with `repo` scope) for `gh`
  CLI auth during the install.

- Your **SSH private key** (the one that matches
  `secrets/krzysiek.age.pub`) so `agenix rekey` can decrypt master secrets.

- Write access to the repo's remote (you will push the new host key).

### What is nixos-facter?

This repo uses **declarative hardware** via `nixos-facter` instead of the
traditional `nixos-generate-config`. The result is a committed
`hosts/soyo/facter.json` that captures every PCI device, kernel module,
disk ID, and USB controller in a machine-readable report — no generated
`hardware-configuration.nix` that needs regeneration after every kernel
update. The report is already committed for Soyo; on a fresh machine you
would run `nixos-facter` first.

---

## Step 1: Boot the live ISO

Boot Soyo from the NixOS live USB. The firmware should be configured as
described in the design doc:

- **UEFI only** (CSM/Legacy off)
- **"State After G3" = S0** (powers on after power loss)
- **TPM 2.0 enabled** (visible as `MSFT0101` under `tpm_crb`)

After boot, confirm networking:

```bash
ip -4 addr show
```

Look for an address on `enp1s0` (wired) or `wlp2s0` (WiFi). You need a routable
IP on the LAN that reaches the internet and GitHub.

---

## Step 2: Set up SSH key and GitHub auth

### SSH key (for agenix)

Your SSH private key must be on the live ISO so `agenix rekey` can decrypt
master-encrypted secrets:

```bash
# Find Soyo's live ISO IP from the output of `ip -4 addr show`.
# Then, from YOUR WORKSTATION:
#   scp ~/.ssh/soyo_ed25519 nixos@<soyo-ip>:~
#
# Back on Soyo's live ISO:
mkdir -p -m 700 ~/.ssh
# The scp'd file lands as soyo_ed25519; rename to id_ed25519 to match the
# live ISO masterIdentities path in modules/parts/soyo.nix:
mv ~/soyo_ed25519 ~/.ssh/id_ed25519 2>/dev/null || echo "Paste manually if scp failed"
chmod 600 ~/.ssh/id_ed25519
```

Verify the key works:

```bash
echo "test" | nix run nixpkgs#rage -- -e -i ~/.ssh/id_ed25519 -o /tmp/.age-test 2>/dev/null \
  && nix run nixpkgs#rage -- -d -i ~/.ssh/id_ed25519 /tmp/.age-test 2>/dev/null | grep -q test \
  && echo "SSH key OK" && rm -f /tmp/.age-test
```

### GitHub CLI (for git auth)

```bash
nix profile install nixpkgs#gh
gh auth login
# Follow the prompts to authenticate with your PAT or browser flow.
gh auth status   # Expected: "Logged in to github.com as <you>"
```

---

## Step 3: Clone the repo

```bash
gh repo clone knirski/nix-config
cd nix-config
```

Enable experimental features so every nix command works without the
`--extra-experimental-features` flag:

```bash
mkdir -p ~/.config/nix
grep -qxF "experimental-features = nix-command flakes" ~/.config/nix/nix.conf 2>/dev/null \
  || echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

Verify:

```bash
git log --oneline -1   # Expected: a recent commit hash
```

---

## Step 4: Partition and format (disko)

**This wipes the target disk.** Run it only after confirming the disk is correct.

```bash
sudo nix run github:nix-community/disko -- --mode disko hosts/soyo/disko.nix
```

What this does (defined in `hosts/soyo/disko.nix`):

1. Creates a **GPT** partition table on the disk.
2. An **EFI System Partition** (1 GB, vfat) mounted at `/boot`.
3. A **LUKS2** partition filling the rest of the disk (`crypted`).
4. A **Btrfs** filesystem inside the LUKS container with four subvolumes:
   - `root` — mounted at `/`, wiped to a blank snapshot every boot
   - `nix` — durable, mounted at `/nix`
   - `persist` — durable anchor for state that survives reboots, at `/persist`
   - `snapshots` — local snapshot target, at `/snapshots`

Verify:

```bash
mount | grep /mnt
# Expected: 5 lines — root, /nix, /persist, /snapshots (btrfs), /boot (vfat)
```

---

## Step 5: One-time bootstrap steps

Three manual steps the running system depends on. The disko layout creates
the subvolumes but does not create the blank snapshot or SSH keys.

### (a) Root-blank snapshot

The initrd restores `root` from this snapshot every boot (impermanence):

```bash
if sudo btrfs subvolume list -t /mnt | grep -q root-blank; then
  echo "root-blank already exists — skipping"
else
  sudo mkdir -p /mnt-top
  sudo mount -t btrfs -o subvolid=5 /dev/mapper/crypted /mnt-top
  sudo btrfs subvolume snapshot -r /mnt-top/root /mnt-top/root-blank
  sudo umount /mnt-top
fi
sudo btrfs subvolume list -t /mnt | grep root-blank   # verify
```

### (b) Initrd SSH host key (break-glass unlock)

Lives on the unencrypted ESP (`/boot`) so the initrd can use it before
LUKS is unlocked:

```bash
if sudo [ -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key ]; then
  echo "initrd SSH key already exists — skipping"
else
  sudo install -d -m 700 /mnt/boot/initrd-ssh
  sudo ssh-keygen -t ed25519 -N "" -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key
fi
sudo ls -la /mnt/boot/initrd-ssh/   # verify
```

### (c) Stage-2 host key (for agenix)

Lives under `/persist` so agenix can decrypt secrets at boot:

```bash
if sudo [ -f /mnt/persist/etc/ssh/ssh_host_ed25519_key ]; then
  echo "stage-2 SSH key already exists — skipping"
else
  sudo install -d -m 700 /mnt/persist/etc/ssh
  sudo ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
fi
sudo ls -la /mnt/persist/etc/ssh/   # verify
```

---

## Step 6: Enroll Soyo in agenix and rekey secrets

Secrets in this repo use the **two-layer rekeyFile flow** (see
[docs/secrets.md](secrets.md) for the full explanation):

1. Master-encrypted `.age` files in `secrets/` are decryptable by the
   operator's SSH key.

2. `agenix rekey` decrypts each master file and re-encrypts it for
   Soyo's host key, writing the result to `secrets/rekeyed/soyo/`.

3. At boot, agenix on Soyo decrypts the rekeyed files with the host
   key placed at `/persist/etc/ssh/`.

**Before we can rekey, `secrets/soyo.pub` must contain the real host public key**
(instead of the dummy placeholder used for the build):

```bash
# Overwrite the placeholder with the real key
sudo cat /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub > secrets/soyo.pub
head -1 secrets/soyo.pub | grep -q ssh-ed25519 \
  && echo "Real key installed" || echo "ERROR: not an SSH public key!"
```

Now rekey (this builds the devshell, which takes a few minutes the first time):

```bash
nix develop '.#' -c agenix rekey
ls -la secrets/rekeyed/soyo/   # verify: 8 .age files
```

Commit and push the new host key and rekeyed secrets:

```bash
git add secrets/soyo.pub secrets/rekeyed/
git commit -m "feat: enroll soyo agenix recipient and rekey secrets"
git push
```

---

## Step 7: Install

```bash
sudo nixos-install --flake .#soyo
```

This builds Soyo's closure from the flake and activates it on the mounted
filesystem. `nixos-install` exits 0 on success.

After successful install:

```bash
# Clean up your SSH key from the live ISO before discarding the USB
rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub
```

**Reboot** into the installed system. After reboot, TPM should auto-unlock,
LAN DHCP/DNS should be running, and all secrets decrypted.

---

## Step 8: Post-install enrollment

### Enroll TPM (if not auto-detected during install)

If TPM auto-unlock was not configured during install, enroll manually:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/luks
```

Verify:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/luks | grep -i tpm
```

After Secure Boot setup (see [docs/recovery.md](recovery.md) for the Phase 2
procedure), re-enroll against PCR 0+2+7 for stronger tamper detection.

### Post-install deploy from a workstation

Update `modules/parts/soyo.nix` to point `masterIdentities` to your
workstation's SSH key path (e.g. `/home/krzysiek/.ssh/soyo_ed25519`)
instead of the live ISO path. Then from any workstation on the LAN:

```bash
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --sudo
```

> **First remote deploy gotcha:** The freshly installed system runs a base
> config that may not yet include `nix.settings.trusted-users` or
> `sudo` passwordless escalation (these are added in
> `modules/nixos/base.nix` and `modules/nixos/users.nix`). If the remote
> deploy fails, build locally on Soyo once first:
>
> ```bash
> git pull && sudo nixos-rebuild switch --flake .#soyo
> ```
>
> After that activation, remote deploys work.

---

## Step 9: Validate

- `enp1s0` comes up with the `dwmac_motorcomm` driver
- Blocky answers DNS on port 53 and filters known ad domains
- dnsmasq hands out DHCP leases with the correct nameserver option
- `soyo.home.arpa` resolves and clients resolve hostnames in `home.arpa`
- TPM auto-unlock works on reboot
- agenix secrets are decrypted (`ls /run/agenix/`)
- Backups to the Synology run and restore drills pass

---

## Subsequent deploys

For normal config-only changes, use the direct deploy path from a workstation on the LAN:

```bash
nix develop '.#' -c nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

If DNS is not working yet, replace `krzysiek@soyo` with `krzysiek@10.0.0.9`.

Use deploy-rs when secrets changed and you want rekey + deploy in one step:

```bash
nix develop '.#' -c agenix rekey
deploy .#soyo

```bash
nix develop '.#' -c agenix rekey
nix develop '.#' -c nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

See [`docs/update-and-rollback.md`](update-and-rollback.md) for the full
update workflow and rollback options.

## Recovery

If something goes wrong during or after install — TPM unlock fails, a
deploy breaks networking, or the disk needs replacement — see the recovery
runbook at [`docs/recovery.md`](recovery.md).
