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

The subtle lesson from this session: the persisted-path inventory has to follow **systemd runtime semantics**, not just directory names. Services that use `DynamicUser=true` plus `StateDirectory=` often write under `/var/lib/private/<name>`, even when the friendly path looks like `/var/lib/<name>`. Alloy was the concrete example: its journal cursor lived under `/var/lib/private/alloy`, so reboots dropped the cursor until that private path was added to the inventory.

## DNS/DHCP: Blocky + dnsmasq

**Fork: AdGuard Home vs Blocky + dnsmasq.** AdGuard is a single-module solution with a UI and built-in DHCP. Not chosen because AdGuard's YAML file pulls against declarative config (`mutableSettings = false` fights the app), its DHCP server is thin next to dnsmasq, and one process couples DNS and DHCP into one blast radius. Blocky handles DNS + ad-block, dnsmasq handles DHCP + PTR, glued by a conditional forward — component isolation and declarative purity over fewer moving parts.

## Secrets: agenix with rekeyFile flow

**Fork: agenix or sops-nix.** Both encrypt secrets at rest. agenix + agenix-rekey's `rekeyFile` flow gives two layers: master-encrypted (operator key) and per-host rekeyed (host SSH key). The operator key decrypts all secrets; the host key only decrypts its own. sops-nix uses a similar model but needs a separate `.sops.yaml` mapping. Picked agenix-rekey for the clearer rekeying workflow and tighter nixpkgs integration.

## Backups: restic

**Fork: restic, rustic, or kopia.** All three do encrypted, deduplicated off-host backups. Only restic has a first-class NixOS module (`services.restic.backups`). rustic and kopia mean hand-rolling systemd timers. Picked restic for the integration gain — one line enables a timer with prune and check. The encrypted restic repo is safe on the Synology even though it's a shared NAS.

## Boot: TPM Phase 1 → Limine Secure Boot Phase 2

**Fork: PCR binding strategy.** PCR 7 (Secure Boot state) is stable across kernel updates and gives unattended auto-unlock. PCR 0+2+7 adds firmware integrity checks but requires Secure Boot. Phased intentionally: Phase 1 means the box is already usable unattended; Phase 2 (M3) hardens without a deployment pause.

**Fork: Limine or lanzaboote.** lanzaboote produces signed UKIs but was dropped from nixpkgs's `lanzaboote-tool` in 2025 for maintenance gaps. Limine's Secure Boot module forces safe defaults (enrolled config, checksum validation, editor locked). Picked Limine for in-tree stability on `nixos-unstable`.

The subtle lesson from the Secure Boot cutover: on an impermanent root, `sbctl`'s private key directory is real host state. The current signed generation can still boot even after those keys are lost, because firmware only needs the already-signed Limine EFI binary plus the enrolled certificates. The *next* `nixos-rebuild` is where the failure appears: the nixpkgs Limine installer calls `sbctl sign` on `BOOTX64.EFI` during activation, and that requires the private keys under `/var/lib/sbctl`. That made `/var/lib/sbctl` part of the persisted-path inventory. Another nuance: `sbctl status` may still report `Installed: ✗ sbctl is not installed` because Limine signs the EFI binary directly and does not populate sbctl's file database. In this setup, successful Secure Boot boots and successful future deploys are the real checks.

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
- **Custom landing dashboards only.** A first pass at a monolithic "Soyo Appliance" dashboard was dropped because Node Exporter Full (1860) already covers generic host internals far better. The custom dashboards came back later, but with a narrower job: a generic **Fleet Overview** landing page and a role-specific **Soyo Control Plane** drilldown. Research with `gh` across real repos found the same split repeatedly — fleet/host summaries (for example Misterio77's `hosts.json`) and service-status dashboards (for example Swarsel's `service-status.json`) work well as home pages, while imported community dashboards stay the deep dives. The rule that survived: hand-written dashboards may summarize and route, but they should not try to reimplement the detailed dashboards.

## Host-local network namespaces

`hosts/soyo/reservations.nix` stays the appliance truth for DHCP and forward/reverse DNS because those roles are critical. Observability needs more shape than `{ name; mac; ip; }`, though, so the repo adds `hosts/soyo/network.nix` as an adjacent namespace instead of mutating the reservation schema. That keeps the critical path boring while still giving Grafana and Prometheus richer labels, extra off-LAN targets, and future room for inventory metadata.

## What's deferred to M3/M4

- **Secure Boot** (M3) — Limine secureBoot, sbctl key enrollment, PCR 0+2+7 re-enroll
- **Laptop host and deploy-rs** (M4) — desktop modules, multi-host orchestration
- **Services** (M4) — Jellyfin, Home Assistant, etc. over NFS to the Synology

## Observability backend config: researching against real production repos

Loki, Alloy, and Tempo are complex — their configs are deep and poorly documented. Each went through a research-then-apply cycle.

### The research method: `gh` over `web_search`

Searched GitHub for production-grade configs from organizations that run these tools at scale. For Loki, searched for `filename:loki-config.yaml repo:grafana/...` and `language:yaml target: all` on respectable repos. For Alloy, searched for `otlp.enabled path:config.alloy` and `loki.source.journal` across the grafana org and third-party NixOS configs. For Tempo, the `services.tempo.settings` module from nixpkgs was the authoritative source.

**The guideline: check what production users actually ship, not what the docs say you can do.** Docs show every possible knob; production configs show what matters.

### Loki: dropping `common.ring` and `-target=all`

Early config had a `common.ring` stanza and ran Loki with `-target=all`. Both are unnecessary at single-node scale.

**`common.ring`** configures the hash ring for multi-tenant ingesters — it emits warnings even on single-node deployments because Loki tries to join the ring regardless. Production single-node configs (grafana/loki examples, `reference-loki-config.yaml`) don't configure rings — they let defaults handle it. Dropped it. Warnings gone.

**`-target=all`** is the documented way to run single-binary mode, but Loki `3.7.2` defaults to `all` when no target is specified. Explicitly specifying it just adds a redundant CLI flag. Dropped it — one less thing to maintain.

Other production-aligned defaults:
- `allow_structured_metadata = false` — avoids unnecessary parsing overhead
- `analytics.reporting_enabled = false` — no telemetry home
- `compactor.retention_enabled = true` — enable log retention via the compactor (not just the table manager)
- `ingester.lifecycler.final_sleep = "0s"` — speeds up shutdown; production configs set this

### Alloy: loopback-only, `--disable-reporting`, and cursor persistence

Alloy's config was already idiomatic — `loki.source.journal` scraping local systemd journals and forwarding to `loki.write`, with `prometheus.exporter.unix` for node metrics. Three production patterns mattered in the end:
- **Loopback ports only** (`127.0.0.1:xxxxx`) for all collectors — no LAN-facing listeners. The collectors serve local scrapers (Prometheus, Loki write), not the network.
- **`--disable-reporting`** CLI flag — Alloy phones home by default. Production configs suppress this.
- **Persist the journal cursor** on an impermanent host. Alloy stores `loki.source.journal` positions under `/var/lib/private/alloy/data-alloy/.../positions.yml` because the unit uses `DynamicUser=true` and `StateDirectory=alloy`. Without persisting that private directory, every reboot makes Alloy start over from `max_age`, which means Loki is ingesting logs but Grafana's recent windows can still look empty until Alloy catches up.

The practical rule: on a wiped-root system, treat `StateDirectory=` paths as first-class state. Persist them explicitly, and keep `loki.source.journal.max_age` short enough that a deliberate state wipe still recovers recent logs quickly.

### Tempo: from raw systemd to `services.tempo`

Tempo was the last observability component to get idiomatic. The original config defined Tempo as a manual systemd service with raw YAML — skipping the nixpkgs module entirely.

The `services.tempo.settings` module converts attrsets to the Tempo YAML config, handles user/group creation, and generates the systemd unit. Moving to it fixed several things:
- **Static user** (`users.users.tempo`) instead of `DynamicUser` — Tempo needs writes to `/var/lib/tempo/traces` (OWNED by tempo, not a runtime bind-mount), which DynamicUser breaks. `lib.mkForce false` on the module's DynamicUser default.
- **Resource isolation** matching the rest of the stack (`MemoryMax=512M`, `CPUQuota=20%`, `Nice=10`).

### Tempo metrics-generator: why it's needed even in single-binary mode

TraceQL's `rate()` function needs pre-computed span metrics. Without a metrics-generator, the querier returns `"empty ring"` — there's no module registered to process rate queries. This isn't documented anywhere obvious; the Grafana Explore UI shows the error before you know the config is missing.

Adding the metrics-generator in single-binary mode requires three things:

1. **`metrics_generator.storage.path`** — the generator writes its own WAL (separate from the ingester WAL)
2. **`metrics_generator.processor.{span_metrics,service_graphs}`** — enables the processors that compute metrics from spans
3. **`metrics_generator.ring.kvstore.store = "inmemory"`** — single-node ring, same pattern as the ingester

The `metrics_generator.processors` override goes at the top-level config, **not** inside `overrides` — Tempo 2.10.x rejects it there with `field metrics_generator not found in type overrides.legacyConfig`. Defaults to `["span-metrics", "service-graphs"]` when the generator is configured.

Also needed: `querier.frontend_worker.frontend_address` pointing at the `query_frontend` module address — without this the querier can't reach the frontend in single-binary mode.

### `localhost` vs `127.0.0.1`: why the hard-coded IP

Soyo's observability stack uses `127.0.0.1` everywhere — not `localhost`. The reason isn't vanity; it's reliability.

`localhost` resolves to both `127.0.0.1` (IPv4) and `::1` (IPv6) via `/etc/hosts`. `curl http://localhost:4318` might pick `::1` in a dual-stack environment. But Tempo (and most Go services) bind to a specific address via `http_listen_address` — if that's `127.0.0.1`, an IPv6 connection fails. The symptom is silent: curl connects, nothing responds, trace generators silently drop data.

The fix (`0af140c`): 20 replacements across Prometheus scrape targets, Loki bind addresses, Alloy push URLs, Grafana datasource URLs, dashboard templating values, trace generator curl targets, and the grafana-alert-setup base URL. Every internal loopback connection uses the explicit IPv4 address.

### Persisted directories need ownership, not just presence

Another impermanence gotcha showed up during a full observability wipe. Recreating `/persist/var/lib/grafana`, `/persist/var/lib/loki`, `/persist/var/lib/tempo`, or `/persist/var/lib/prometheus` as bare directories is not enough — they come back as `root:root`, the bind mounts succeed, and the services then fail later with ordinary filesystem errors (`permission denied`, failed symlink creation, missing WAL directories).

The fix is declarative ownership in the `preservation` inventory for the top-level persisted service directories themselves. `preservation` generates the tmpfiles entries for those paths, so a second conflicting rule gets ignored. Plain tmpfiles rules still make sense for nested helper directories such as Tempo's generator WAL and trace storage. Presence answers “does the path survive reboot”; ownership answers “can the service actually use it after a wipe or recovery.” On an impermanent host, both are part of the state contract.

### ntfy alert rendering: templates over attachments

Grafana's webhook contact point sends the full alerting JSON payload to the configured URL. Without templating, ntfy shows that raw JSON as the notification body — unreadable, with sensitive data visible.

The fix uses ntfy's built-in Go template engine (`?template=yes` query parameter on the topic URL):

```
https://ntfy.sh/soyo-alerts?template=yes&title=%7B%7B.title%7D%7D&message=%7B%7B.message%7D%7D&priority=5&tags=warning,soyo
```

Grafana's webhook JSON includes `title` and `message` fields at the top level — already populated by Grafana's default notification template. ntfy extracts them, renders them as the notification title and body, and consumes the JSON payload. No attachment, no raw JSON, no proxy needed.

The `%7B%7B` is URL-encoded `{{` (Golang template syntax). jq constructs the URL via string concatenation in the provisioning script.

### Alert tolerance: 5m not 2m

Blocky and dnsmasq `for` was 2 minutes — enough for a `nixos-rebuild` to trigger spurious alerts when services restart. Raised to 5 minutes. A genuine outage still fires quickly (5m), but a deployment restart is invisible.

Prometheus scrapes every 60s, so 5m means at most 5 consecutive failed scrapes before alerting — two more than 2m, which is the right extra margin for scheduled maintenance without trading off real outage detection speed.

### Dashboard folder over tags

Three community dashboards (Blocky, dnsmasq, Node Exporter) used `tags = ["soyo"]` to group them under a common label. Grafana's folder system (`folder = "soyo"` on the provider) groups them natively in the UI sidebar. Tags stay for functional search (e.g. `dnsmask`, `blocky`, `linux`, `node-exporter`) — organizational grouping moves to the folder.

## Trace generators: Python → shell + `writeShellApplication`

Soyo sends structured traces into Tempo so we can see service lifecycle events (boot, activation, health checks, backups) alongside metrics and logs. Four generators run on timers.

### The rewrite: from Python to shell

The first implementation used Python `writeShellApplication` scripts. Each tracer imported `subprocess`, `json`, `uuid`, and `datetime` — four Python modules to construct an HTTP POST with a JSON body. For something that boils down to `uuidgen | jq | curl`, this was overbuilt.

The rewrite followed a simple principle: **"For HTTP calls use simplest possible commands."**

Every tracer now follows this pattern:
```bash
TRACE_ID=$(uuidgen | tr -d -)
SPAN_ID=$(uuidgen | tr -d - | cut -c1-16)
NOW_NS=$(date +%s%N)
jq -nc --arg id "$TRACE_ID" --arg span "$SPAN_ID" --arg ts "$NOW_NS" '...' \
  | curl -sS -X POST -H 'Content-Type: application/json' -d @- http://localhost:4318/v1/traces
```

Dependencies: `curl`, `jq`, `util-linux` (for `uuidgen`). No Python, no Go, no interpreters beyond bash.

### Four tracers, four patterns

- **`boot-trace`** (oneshot, runs at boot): parses `systemd-analyze blame` with `awk`, extracts the top 20 slowest services, builds a trace with child spans for each. The `head -20` + `set -o pipefail` combo caused exit 141 (SIGPIPE) — fixed by appending `|| true` to the piped pipeline.
- **`activation-trace`** (path unit, triggers on `/run/current-system`): reports NixOS activation latency. Simple `stat` on the system symlink and an uptime check.
- **`health-trace`** (timer, every 60s): runs `systemctl is-active --quiet multi-user.target` as a span. Replaced the original `systemctl is-system-running --wait` which blocks indefinitely.
- **`backup-trace`** (timer, daily): simple trace span marking backup window start. Stub — actual backup metrics come from the restic Prometheus exporter.

### `writeShellApplication` over raw `writeShellScript`

`writeShellApplication` wraps the script in `shellcheck` validation and adds runtime dependencies to `PATH`.

**Three recurring gotchas** with `writeShellApplication`:
1. **Missing `runtimeInputs`** — `uuidgen` lives in `util-linux`, not in bash. Each tracer that uses `uuidgen` needs `pkgs.util-linux` in `runtimeInputs`. Forgetting this produces `command not found` at runtime, not at build time (shellcheck can't know about commands used in `$(…)` expansions).
2. **`set -o pipefail` + `head` = SIGPIPE** — `head -N` closes its stdin after N lines, which sends SIGPIPE to the producer. With `pipefail`, this becomes exit 141. The fix is `producer | head -N || true`. Only `boot-trace` hits this (parsing `systemd-analyze blame`).
3. **`CREDENTIALS_DIRECTORY` only exists under systemd** — `LoadCredential=` mounts secrets into a per-unit directory at `$CREDENTIALS_DIRECTORY`. Running the script directly (e.g. for debugging) means the variable is unset. The `set -eu` fix: `: "${CREDENTIALS_DIRECTORY:=/dev/null}"` at script top.

## Grafana alert rule provisioning: old API vs new API

Grafana 13 replaced the legacy `/api/v1/provisioning/alert-rules` with `/apis/rules.alerting.grafana.app/v0alpha1/namespaces/{ns}/alertrules`. The docs say to use the new one. The reality is different.

### The new API is broken in 13.0.3

Tested two formats against the `/apis/v0alpha1` endpoint:

1. **Kubernetes-style** (`apiVersion: "rules.alerting.grafana.app/v0alpha1"`, `kind: "AlertRule"`, `metadata.name`, `spec.expressions`, `spec.trigger.interval`): returned `valid orgId expected in namespace` (the namespace parser can't parse its own namespace format).
2. **Minimal payload** with `spec.for: "5m"`: returned `forbidden: invalid duration format: empty duration string` — the duration validator rejects `"5m"` as empty.

Both 403/500 errors, neither actionable. The old API works perfectly with two missing fields:

### What was actually broken: `ruleGroup` and `orgID`

The alert rule POST body was missing `ruleGroup` (required for grouping rules) and `orgID` (required for multi-org installations). Both are `required` fields in the API schema but neither was in the error messages. The old config copied the format from pre-13 docs and added `folderUID`, but skipped these two.

The fix (`65edb12`): add `"ruleGroup": "soyo", "orgID": 1` to every rule payload. All four rules provision successfully.

### `LoadCredential` over `cat` on agenix paths

The original script read secrets via `$(cat /run/agenix/...)` inline. This leaks the agenix internal path into the script text (stored in the Nix store). `LoadCredential=` mounts secrets at `$CREDENTIALS_DIRECTORY` at runtime — the agenix path never appears in the script. This is the idiomatic systemd pattern for secret injection.
