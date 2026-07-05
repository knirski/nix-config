# Update & Rollback

How to update Soyo to the latest `nixos-unstable` and roll back when an update goes wrong.

## Routine update

The day-2 remote deploy uses native `nixos-rebuild --target-host` — your workstation builds, Soyo activates. There are two useful paths:

### Config-only deploy (fast path, no secret changes)

```sh
nix develop '.#' -c nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --use-remote-sudo
```

Use this when you are changing NixOS config, dashboards, alerts, services, or docs and **none of the master-encrypted secret files changed**. It builds the full closure locally, copies it to Soyo over SSH, and activates it remotely. Soyo's N150 never compiles. If DNS isn't working, use `krzysiek@10.0.0.9`.

### Secret-changing deploy (rekey + deploy)

```sh
./scripts/deploy-soyo.sh
```

This runs:

1. `agenix rekey` — re-encrypts every master `.age` secret for Soyo's host key. Run this on your workstation with your SSH private key available (the `masterIdentities` in `modules/parts/soyo.nix` must point to it). Failure here means Soyo gets stale secrets.
2. `nixos-rebuild switch --target-host krzysiek@soyo --use-remote-sudo` — builds the full closure locally, copies it to Soyo over SSH, and activates it remotely.

## Updating nixpkgs

```sh
nix flake lock --update-input nixpkgs
```

Then deploy normally. Confirm `enp1s0` still comes up after the deploy — the `dwmac_motorcomm` driver must survive each kernel bump.

After M3, every Limine reinstall also needs the local `sbctl` private keys. Those live under `/var/lib/sbctl`, which is persisted from `/persist`. If activation ever fails with `There are no sbctl secure boot keys present. Please generate some.`, the durable key state is missing: return firmware to Setup Mode, recreate the keys with `sbctl create-keys` + `sbctl enroll-keys -m`, deploy once before rebooting again, then re-enable Secure Boot.

After a kernel/initrd/bootloader update, TPM PCRs should stay stable (Phase 2 binds
PCR 0+2+7, which does not change across software updates). If auto-unlock still fails
for another reason, use break-glass passphrase unlock, then re-enroll:

```sh
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/luks
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0,2,7 /dev/disk/by-partlabel/luks
```

See [recovery.md](./recovery.md) for the full break-glass flow.

## Rollback

NixOS keeps previous generations in the boot menu. Three options:

### Rollback to previous generation (quickest)

```sh
sudo nixos-rebuild switch --rollback
```

This flips the current system profile symlink to the previous generation immediately. If the bad update broke SSH or networking, use the boot menu instead.

### Boot a previous generation from the boot menu

At boot, Limine shows a numbered list. Pick the previous generation. If it works, make it permanent:

```sh
sudo nixos-rebuild switch --rollback
```

### Full revert from a bad nixpkgs update

```sh
# Revert the flake lock to the known-good nixpkgs revision
git checkout flake.lock
# Or: nix flake lock --override-input nixpkgs github:NixOS/nixpkgs/<known-good-rev>
./scripts/deploy-soyo.sh
```

## Testing before committing

```sh
# Build and activate, but don't make it the boot default:
nixos-rebuild test --flake .#soyo --target-host krzysiek@soyo --use-remote-sudo

# If it's good, make it permanent:
ssh krzysiek@soyo sudo nixos-rebuild switch
```

## Manual rekey

If you add a new secret or change a master-encrypted file, rekey before deploy:

```sh
nix develop '.#' -c agenix rekey
git add secrets/rekeyed/soyo/
git commit
```

Secrets are rekeyed automatically by `deploy-soyo` as the first step. If you need a faster iteration without rekeying, run:

```sh
nix develop '.#' -c nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --use-remote-sudo
```
