# Soyo — First Install from Live USB

## Prerequisites

- NixOS 26.05 ISO with `enp1s0` support (in-tree `dwmac_motorcomm`). WiFi (`RTL8852BE`) or USB Ethernet as fallback.
- The target disk: `/dev/disk/by-id/ata-PELADN_512GB_20250522100164` (adjust in `disko.nix` if different).
- Network: live ISO gets an IP via DHCP on the LAN uplink.
- A local checkout of this repo with write access to the remote (for pushing the agenix recipient).

## 1. Boot the live ISO and clone

```bash
# Optional: bring up WiFi if wired is down
# iwctl station wlan0 connect <SSID>

# Clone the config
git clone https://github.com/knirski/nix-config
cd nix-config
```

## 2. Partition and format

Wipes the target disk and creates the LUKS + Btrfs layout from `disko.nix`:

```bash
sudo nix run github:nix-community/disko -- --mode disko hosts/soyo/disko.nix
```

`/mnt` is now mounted with `root` at `/mnt`, `nix` at `/mnt/nix`, `persist` at `/mnt/persist`, and `/boot` at `/mnt/boot`.

## 3. Create the blank snapshot and SSH keys

Three one-time bootstrap steps the running system depends on:

```bash
# (a) Root-blank snapshot (the initrd rollback target)
mkdir -p /mnt-top
mount -o subvol=/ /dev/mapper/crypted /mnt-top
btrfs subvolume snapshot -r /mnt-top/root /mnt-top/root-blank
umount /mnt-top

# (b) Initrd break-glass SSH host key on the ESP
install -d -m 700 /mnt/boot/initrd-ssh
ssh-keygen -t ed25519 -N "" -f /mnt/boot/initrd-ssh/ssh_host_ed25519_key

# (c) Stage-2 host key on /persist (so agenix can decrypt on first boot)
install -d -m 700 /mnt/persist/etc/ssh
ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/ssh/ssh_host_ed25519_key
```

## 4. Enroll the Soyo agenix recipient

Before `nixos-install`, add Soyo's host key to the recipient list so secrets are decryptable on first boot:

```bash
# Derive the age public key from the stage-2 host key (placed in step 3c)
nix shell nixpkgs#ssh-to-age --command sh -c '                         \
  ssh-to-age < /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub            \
             > secrets/soyo.age.pub                                     '
```

Now edit `secrets/secrets.nix` and add `soyo` alongside `krzysiek`:

```diff
 let
   krzysiek = builtins.readFile ./krzysiek.age.pub;
+  soyo = builtins.readFile ./soyo.age.pub;
 in
 {
-  "root-password.age".publicKeys = [ krzysiek ];
-  "krzysiek-password.age".publicKeys = [ krzysiek ];
-  "restic-password.age".publicKeys = [ krzysiek ];
-  "ntfy-token.age".publicKeys = [ krzysiek ];
+  "root-password.age".publicKeys = [ krzysiek soyo ];
+  "krzysiek-password.age".publicKeys = [ krzysiek soyo ];
+  "restic-password.age".publicKeys = [ krzysiek soyo ];
+  "ntfy-token.age".publicKeys = [ krzysiek soyo ];
 }
```

Then rekey all existing secrets to include the new recipient, commit, and push:

```bash
nix shell nixpkgs#agenix --command agenix -r
git add secrets/
git commit -m "feat: enroll soyo agenix recipient"
git push
```

> **Note:** `agenix -r` needs your SSH private key to decrypt the existing secrets. If you're on the live ISO, copy your key first:
> `install -d -m 700 ~/.ssh && cat > ~/.ssh/id_ed25519` then paste it (or use `scp`/`ssh-agent`).

## 5. Install

```bash
sudo nixos-install --flake .#soyo
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

## Changing a password

```bash
# 1. Generate a new SHA-512 password hash
mkpasswd -m sha-512

# 2. Edit the encrypted secret — agenix decrypts, opens $EDITOR, re-encrypts
#    Replace the old hash with the new one, save, and exit.
nix shell nixpkgs#agenix --command agenix -e secrets/root-password.age

# 3. Commit and deploy
git add secrets/root-password.age
git commit -m "chore: update root password"
nixos-rebuild switch --flake .#soyo --target-host krzysiek@10.0.0.9 --use-remote-sudo
```

Same flow for `krzysiek-password.age` or any other secret.

## Recovery paths

See the recovery runbook at `docs/recovery.md` (not yet written) or the [design doc](../docs/superpowers/specs/soyo-dns-dhcp-appliance.md) for TPM, remote initrd SSH, and direct-link rescue procedures.
