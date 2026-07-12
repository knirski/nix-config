# Update & Rollback

How to update Soyo on its pinned NixOS 26.05 release branch and roll back when
an update goes wrong. Moving to another release or to `nixos-unstable` is a
separate migration, not a routine lock-file refresh.

## Routine update

The day-2 remote deploy uses deploy-rs with magic rollback. Run from your workstation inside the dev shell (`nix develop`):

### Config-only deploy (fast path, no secret changes)

```sh
nix develop '.#' -c deploy .#soyo
```

deploy-rs runs `nix flake check` first (validates the deploy schema and activation scripts), builds the closure, copies it to the target over SSH, activates with magic rollback. If the activation fails or you don't confirm, it rolls back automatically.

### Secret-changing deploy (rekey + deploy)

```sh
nix develop '.#' -c bash -c 'agenix rekey && deploy .#soyo'
```

This runs:

1. `agenix rekey` — re-encrypts every master `.age` secret for Soyo's host key. Run this on your workstation with your SSH private key available (the `masterIdentities` in `modules/parts/soyo.nix` must point to it). Failure here means Soyo gets stale secrets.
2. `deploy .#soyo` — builds, copies, and activates with magic rollback.

## Fallback: native nixos-rebuild

If deploy-rs is unavailable, the native build + remote activation still works:

```sh
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```

Use this when you are changing NixOS config, dashboards, alerts, services, or docs and **none of the master-encrypted secret files changed**. It builds the full closure locally, copies it to Soyo over SSH, and activates it remotely. Soyo's N150 never compiles. If DNS isn't working, use `krzysiek@10.0.0.9`.

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
nix develop '.#' -c bash -c 'agenix rekey && deploy .#soyo'
```

## Testing before committing

```sh
# Build and activate, but don't make it the boot default:
nixos-rebuild test --flake .#soyo --target-host krzysiek@soyo --sudo

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

Secrets are rekeyed automatically by `deploy .#soyo` as part of the workflow. If you need a faster iteration without rekeying, run:

```sh
nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --sudo
```
