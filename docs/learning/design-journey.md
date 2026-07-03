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

**First-deploy gotcha:** `trusted-users` and `wheelNeedsPassword = false` are required for `--target-host` to work (nix-copy-closure needs trusted-user, sudo needs no TTY). If you add these after `nixos-install`, the first remote deploy fails — you need one local build on Soyo first to activate them.

## Observability: on-box Grafana (later addition)

The spec originally kept dashboards off-box — exporters on Soyo, scraping and storage on the NAS or Grafana Cloud. That's the architecturally clean split: metrics stay up when Soyo is down.

Grafana ended up on Soyo anyway. The reasons:

- **It fits.** Grafana is a ~100 MB Go binary with SQLite. 256 MB MemoryMax and 20% CPUQuota is plenty. It's a guest, same as any other non-critical service.
- **Prometheus** scrapes the local exporters on loopback (zero network overhead) and serves the query API to Grafana. Both are resource-isolated.
- **Self-contained.** No dependency on the NAS or cloud for dashboards. If Soyo is down, the Synology Uptime Kuma probe still covers the liveness gap.
- **The principle didn't justify the friction.** Having to spin up a separate Grafana instance to see CPU graphs for a single-host LAN appliance was more effort than it saved. The guest isolation pattern (MemoryMax, CPUQuota) already protects DNS/DHCP — the extra safety of a separate failure domain wasn't buying much at this scale.

The off-box path stays documented as an alternative for when Soyo graduates to multi-host or the on-box stack becomes a bottleneck.

### Dashboard provisioning: community dashboards vs Grafana's import wizard

Community dashboards from grafana.com bind template variables (`$job`, `$instance`, `$datasource`) that Grafana's UI import wizard resolves interactively. File-based provisioning skips that wizard — variables stay empty and panels show "No data." Four attempts at fixing this, only one survived.

**Attempt 1: sed-only (`\x24{DS_PROMETHEUS}` → `soyo-prometheus`).** Replaced the `${VAR}` form in datasource UIDs. Failed because community dashboards use bare `$job`/`$instance` in PromQL selectors (`instance=~"$node"`, `job=~"$job"`) — these stayed unresolved, and removing them from templating left PromQL like `instance=~""` which matched nothing.

**Attempt 2: sed + jq to set template variable defaults.** Injected current values into `.templating.list[].current` via `jq` so Grafana would resolve them normally. Worked functionally but pulled in `jq` as a build dependency — violating the "pure Nix, no build inputs" constraint. Also fragile: each dashboard's template variable names varied (`ds_prometheus` vs `DS_PROMETHEUS`, `node` meaning "instance" on dashboard 1860).

**Attempt 3: `fillTemplating` — the one that stuck.** A pure-Nix function that walks the entire JSON tree and replaces three patterns using `builtins.replaceStrings`:

1. `${KEY}` → value — datasource UIDs and JSON-embedded refs
2. `"$key"` → `"value"` — bare PromQL template refs in quoted selectors
3. `$key` → value — Grafana builtins like `$__rate_interval` (always → `4m`; see below)

After replacement, template variables are deleted from `templating.list` so Grafana never tries to resolve orphaned references. No `jq`, no `sed`, no build inputs — just `builtins.fromJSON`, `builtins.replaceStrings`, and `lib.mapAttrsRecursive`.

**The guideline that mattered: "Pure Nix, no build inputs."** The jq detour (Attempt 2) was a 6-commit round-trip that got reverted. Each time the solution drifted toward build-time tooling, the constraint pulled it back. The final `fillTemplating` is 30 lines of pure Nix that handles all three community dashboards identically.

### `$__rate_interval` — the 4-hour rabbit hole

Grafana's `$__rate_interval` is a built-in that auto-selects a range vector duration based on scrape interval and time window. On a 5-minute window with 1-minute scrape intervals, it resolved to ~15s — so `rate(…[$__rate_interval])` became `rate(…[15s])`, which returned zero data (1m scrape interval produces only 5 raw data points; a 15s window needs at least 2).

Tested with `gcx`:
```
# Fails at 5m window, returns data at 15m window:
rate(node_pressure_cpu_waiting_seconds_total[1m])   → No data
rate(node_pressure_cpu_waiting_seconds_total[3m])   → data ✓
```

Hardcoding `$__rate_interval` → `4m` in `fillTemplating` (4× scrape interval) gives enough samples without being too coarse. All three community dashboards use it (dnsmasq: 4 refs, blocky: 23, node-exporter: 153). Setting `timeInterval = "60s"` on the datasource would let Grafana auto-resolve correctly, but provisioned datasources are read-only — the hardcode is the actual fix.

### `enabledCollectors` — restrictive, not additive

Another rabbit hole. The original config had:

```nix
enabledCollectors = [ "textfile" "systemd" "processes" "filesystem" ];
```

Commit `0297126` removed it to "let node_exporter enable its full default set." This did restore defaults (CPU, memory, disk, network, hwmon) but **killed `processes` and `interrupts`** — those collectors are opt-in, not default. Dashboard 1860 has panels for both (process counts, interrupt rates, context switches, file descriptors), which went blank.

The NixOS module's `enabledCollectors` is a **restrictive list** — it tells node_exporter which collectors to run via individual `--collector.X` flags, but only activates those explicitly listed. The old list was coincidentally right for the wrong reason (it restricted to four, accidentally including two non-default ones). The correct approach: no `enabledCollectors` (let defaults flow) + `extraFlags` for opt-in collectors:

```nix
extraFlags = [
  "--collector.textfile.directory=/var/lib/prometheus/textfiles"
  "--collector.processes"
  "--collector.interrupts"
];
```

`systemd` was intentionally skipped — it needs `/var/run/dbus/system_bus_socket`, which is blocked by the hardened service sandbox (`ProtectSystem=strict`). Only one panel on dashboard 1860 uses it, and the N150 has no `node_hwmon_fan_*` sensors or `node_power_supply_*` to warrant weakening the sandbox.

### What didn't get added — and why

- **Prometheus self-monitoring (dashboard 19268).** 1,300+ metrics from `localhost:9090/metrics` covering TSDB, query latency, WAL. Low signal-to-noise for 3 scrape targets and ~2,500 series — nothing to optimize.
- **Grafana self-monitoring.** Community dashboards target v10/v11 naming; Grafana 13 renamed half the metrics. `systemctl status grafana` already tells you it's running.
- **Custom "Soyo Appliance" dashboard.** 600 lines of hand-maintained JSON covering CPU, memory, disk, and service status. Node Exporter Full (1860) covers all of it plus 130 more panels. Dropped in `0b8e703`.

## What's deferred to M3/M4

- **Secure Boot** (M3) — Limine secureBoot, sbctl key enrollment, PCR 0+2+7 re-enroll
- **Laptop host and deploy-rs** (M4) — desktop modules, multi-host orchestration
- **Services** (M4) — Jellyfin, Home Assistant, etc. over NFS to the Synology
