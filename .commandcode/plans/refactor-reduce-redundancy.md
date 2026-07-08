# Reduce Redundancies & Modernize

## Duplications Found

| What | Files | Lines Duplicated |
|------|-------|-----------------|
| OpenSSH lockdown | `server.nix` + `workstation.nix` | ~6 (identical) |
| Tailscale auth oneshot | `server.nix` + `workstation.nix` | ~20 (same pattern, different args) |
| Backup (restic + btrbk) | `backup.nix` + `workstation.nix` | ~150 (90% overlap, different namespaces) |
| Empty `command-code.nix` | `command-code.nix` | Whole file (dead code) |
| `scripts/deploy.sh` | `scripts/deploy.sh` | All (deploy-rs does this) |

## Phase 1: Shared `ssh` Aspect

### Create `modules/nixos/ssh.nix`

Shared OpenSSH lockdown aspect. Options: `enable`, `permitRootLogin` (default `"no"`), `ports` (default `[ 22 ]`), `extraConfig` (passthrough).

### Remove from `server.nix` and `workstation.nix`

Delete the `services.openssh = { enable = true; ... }` block in both.

### Wire in `soyo.nix` and `zbook.nix`

Add `ssh` to both assembler aspect lists.

## Phase 2: Shared `tailscale` Aspect

### Create `modules/nixos/tailscale.nix`

Options: `enable`, `authKeyFile`, `extraArgs` (for `--advertise-routes`), `nice` (for systemd service priority).

### Remove from `server.nix`

Delete: `options.lanAppliance.services.tailscale`, `services.tailscale`, `systemd.services.tailscale-auth` (all of it).

### Remove from `workstation.nix`

Delete: `options.workstation.services.tailscale`, the `services.tailscale` enable line, the `systemd.services.tailscale-auth` block.

### Update host configs

- `hosts/soyo/networking.nix`: `lanAppliance.services.tailscale` → `services.tailscaleAuth` with `extraArgs = [ "--advertise-routes=10.0.0.0/24" ]`
- `hosts/zbook/networking.nix`: `workstation.services.tailscale` → `services.tailscaleAuth`

### Wire in assemblers

Add `tailscale` to both `soyo.nix` and `zbook.nix` aspect lists.

## Phase 3: Unify Backup (single aspect for both hosts)

### Rewrite `modules/nixos/backup.nix`

Rename namespace from `lanAppliance.services.backup` → `services.backup`.

Key changes from current `backup.nix`:
- Add `hostName` option (defaults to `config.networking.hostName` — so Soyo explicitly sets `"soyo"`, zbook gets it for free)
- Add `enableTracing` option (default `false` — Soyo opts in)
- Add `enablePromMetrics` option (default `false` — Soyo opts in)
- Make default prune `--keep-daily 7 --keep-weekly 4 --keep-monthly 6` (Soyo adds `--keep-yearly 2` via host config)
- Make `extraOptions` dynamic: `sftp.command` uses `${hostName}-backup@czworaczki.home.arpa` (consistent pattern, both hosts already follow this)
- Keep all existing features (metric bootstrap, OTLP tracing, btrbk, checkOpts)

### Update host backup configs

- `hosts/soyo/backup.nix`: `lanAppliance.services.backup` → `services.backup`, add `enableTracing = true; enablePromMetrics = true;`, keep `pruneOpts` override for yearly
- `hosts/zbook/backup.nix`: `workstation.services.backup` → `services.backup` (no hostName needed, defaults to "zbook")

### Remove from `workstation.nix`

Delete the entire `options.workstation.services.backup` block + `services.restic.backups` + `services.btrbk` config.

## Phase 4: Remove Empty `command-code.nix`

### Delete `modules/nixos/command-code.nix`

All it does is `aspects.nixos.commandCode = {}`. The actual command-code package is already wired via:
- `modules/nixos/base.nix` — overlay
- `modules/home/base.nix` — `home.packages`
- `modules/parts/perSystem.nix` — flake output for dev shell

### Update `modules/default.nix`

Remove `./nixos/command-code.nix` from the import list.

### Update `modules/parts/zbook.nix`

Remove `commandCode` from the aspect list.

## Phase 5: Delete `scripts/deploy.sh`

deploy-rs is the sole deployment tool. The script is unused and duplicates functionality.

## Phase 6: What Remains

### `server.nix` (after extraction)
```nix
{ networking.useNetworkd = true; systemd.network.enable = true;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
  services.earlyoom = { enable = true; freeMemThreshold = 10; freeSwapThreshold = 10; }; }
```
~10 lines instead of 99.

### `workstation.nix` (after extraction)
All functionality extracted. Keep as empty semantic marker aspect so the assembler's `workstation` reference still works. Or delete it and remove from zbook's assembler — **up to you, I'll keep it as empty marker unless you say otherwise.**

## File Change Manifest

| File | Action |
|---|---|
| `modules/nixos/ssh.nix` | **CREATE** |
| `modules/nixos/tailscale.nix` | **CREATE** |
| `modules/nixos/backup.nix` | **REWRITE** |
| `modules/nixos/server.nix` | **SIMPLIFY** (rm OpenSSH + Tailscale) |
| `modules/nixos/workstation.nix` | **SIMPLIFY** (rm OpenSSH + Tailscale + backup) |
| `modules/nixos/command-code.nix` | **DELETE** |
| `modules/default.nix` | Add `ssh.nix` + `tailscale.nix`; rm `command-code.nix` |
| `modules/parts/soyo.nix` | Add `ssh` + `tailscale` to aspect list |
| `modules/parts/zbook.nix` | Add `ssh` + `tailscale`; rm `commandCode` |
| `hosts/soyo/networking.nix` | Rename tailscale namespace |
| `hosts/soyo/backup.nix` | Rename backup namespace; add optional features |
| `hosts/zbook/networking.nix` | Rename tailscale namespace |
| `hosts/zbook/backup.nix` | Rename backup namespace |
| `scripts/deploy.sh` | **DELETE** |

## Verification

After changes:
1. `nix flake check` — passes evaluation, deploy checks, formatting check
2. `nix build .#nixosConfigurations.soyo.config.system.build.toplevel` — builds
3. `nix build .#nixosConfigurations.zbook.config.system.build.toplevel` — builds
4. Assert: no `lanAppliance.services.tailscale` or `workstation.services.backup` references remain in codebase
5. Assert: OpenSSH lockdown, Tailscale auth, restic backup, btrbk snapshots all still functional on both hosts
