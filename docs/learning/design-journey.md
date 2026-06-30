# Design Journey

Why Soyo's config looks the way it does — the forks and the reasons.

## Why Nix and flakes?

Before any of this made sense, the question was: why not just `apt install dnsmasq blocky` on a Debian box?

A shell-scripted server works fine for one machine. The problems start when you want to reproduce it — a replacement after disk failure, a second host, or just remembering what you changed six months ago. With imperative config, the machine is a snowflake: its state is whatever accumulated from every command you ever ran. There's no single source of truth for what's installed, configured, or running.

NixOS solves this by making the entire system a **derivation of configuration**. Every package, every config file, every service is declared in one place. The system is built atomically from that declaration. If it builds, it works; if it breaks, roll back to the previous generation. The machine becomes a function of your config, not an accumulation of manual steps.

**Flakes** are the modern Nix convention for packaging that config: a self-contained unit with locked inputs (`nixpkgs` pinned to a specific revision), a clean entry point, and composable outputs. A flake is version-controllable, reproducible, and sharable across machines. This repo is a single flake that can build any of its hosts.

## Starting point: a single flake

The simplest NixOS flake has one `nixosConfiguration` in `flake.nix` and a `hardware-configuration.nix` from `nixos-generate-config`. That works for one host, but the second host means copying everything. This repo starts multi-host from day one.

**Fork: flake-parts or flat flakes.** A flat flake works for one host. `flake-parts` gives modular outputs (dev shell, formatter, checks, NixOS config) and a module system to compose them. Picked flake-parts: keeps `flake.nix` thin and lets each feature be its own module, shareable across hosts.

**Fork: dendritic or flat imports.** The dendritic pattern (`import-tree` auto-discovers every file under `modules/`) is indirection — you can't see what's imported just by reading the file tree. The alternative is explicit `imports` lists in each host. Picked dendritic for its learning value: it forces understanding the aspect→host wiring, and the docs compensate for the indirection overhead. A future laptop toggles the same shared aspects.

## Filesystem: impermanence

Traditional NixOS has a mutable `/` where services write state freely. That's simple but hides which files actually matter. Impermanence (erase-your-darlings) wipes root each boot and only restores explicitly declared paths. This forces an inventory of persistent state.

**Fork: tmpfs root vs blank-snapshot rollback.** Btrfs snapshots are more storage-efficient (no RAM ceiling), keep a uniform filesystem layout, and interact cleanly with `disko`. Picked blank-snapshot rollback: a `root-blank` readonly snapshot taken once at install, the live `root` restored from it each boot.

**Fork: preservation or impermanence (community module).** `preservation` is newer and less battle-tested than `nix-community/impermanence`. Picked `preservation` deliberately as a learning target — fewer examples, more to understand from first principles. Both solve the same problem: persisting selected paths from a wiped root.

## DNS/DHCP: Blocky + dnsmasq

**Fork: AdGuard Home vs Blocky + dnsmasq.** AdGuard is a single-module solution with a UI and built-in DHCP. Not chosen because AdGuard's YAML file pulls against declarative config (`mutableSettings = false` fights the app), its DHCP server is thin next to dnsmasq, and one process couples DNS and DHCP into one blast radius. Blocky handles DNS + ad-block, dnsmasq handles DHCP + PTR, glued by a conditional forward — component isolation and declarative purity over fewer moving parts.

## Secrets: agenix with rekeyFile flow

**Fork: agenix or sops-nix.** Both encrypt secrets at rest. agenix + agenix-rekey's `rekeyFile` flow gives two layers: master-encrypted (operator key) and per-host rekeyed (host SSH key). The operator key decrypts all secrets; the host key only decrypts its own. sops-nix uses a similar model but needs a separate `.sops.yaml` mapping. Picked agenix-rekey for the clearer rekeying workflow and tighter nixpkgs integration.

## Backups: restic

**Fork: restic, rustic, or kopia.** All three do encrypted, deduplicated off-host backups. Only restic has a first-class NixOS module (`services.restic.backups`). rustic and kopia mean hand-rolling systemd timers. Picked restic for the integration gain — one line enables a timer with prune and check. The encrypted restic repo is safe on the Synology even though it's a shared NAS.

## Boot: TPM Phase 1 → Limine Secure Boot Phase 2

**Fork: PCR binding strategy.** PCR 7 (Secure Boot state) is stable across kernel updates and gives unattended auto-unlock. PCR 0+2+7 adds firmware integrity checks but requires Secure Boot. Phased intentionally: Phase 1 means the box is already usable unattended; Phase 2 (M3) hardens without a deployment pause.

**Fork: Limine or lanzaboote.** lanzaboote produces signed UKIs but was dropped from nixpkgs's `lanzaboote-tool` in 2025 for maintenance gaps. Limine's Secure Boot module forces safe defaults (enrolled config, checksum validation, editor locked). Picked Limine for in-tree stability on `nixos-unstable`.

## Deploy: native nixos-rebuild

**Fork: deploy-rs or native build + copy.** `deploy-rs` adds deploy checks and magic-rollback but needs another flake input. Native `nixos-rebuild --target-host` does local build + remote activation with zero extra dependencies. `deploy-rs` deferred to M4 when a second host makes multi-host orchestration worth it.

## What's deferred to M3/M4

- **Secure Boot** (M3) — Limine secureBoot, sbctl key enrollment, PCR 0+2+7 re-enroll
- **Laptop host and deploy-rs** (M4) — desktop modules, multi-host orchestration
- **Services** (M4) — Jellyfin, Home Assistant, etc. over NFS to the Synology
