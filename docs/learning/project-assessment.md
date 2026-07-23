# Project Assessment — nix-config Multi-Host Flake

*Comprehensive architectural and operational review. Written for maintainers and contributors to understand current state, risks, and prioritized next steps.*

---

## Executive Summary

This is a **production-grade, learning-oriented NixOS/nix-darwin flake** managing four hosts across two roles (LAN appliance + workstations).

This assessment was substantially reconciled on **2026-07-23** (task D1) after
the [repository assessment remediation plan](../superpowers/plans/2026-07-23-repository-assessment-remediation.md)
landed 16 of its 18 work items (C1–M1), fixing real defects across six
categories: **correctness** (C1–C4), **operational** (O1–O3), **role-separation**
(R1, R2), **security** (S1–S4), **host-contract** (H1, H2), and
**reusability** (M1). The table below replaces the previous unqualified
star ratings with dated evidence and named residual risks — including the
defects this plan repaired and two findings it surfaced that are **not**
fixed and require separate human authorization to act on.

| Dimension | Dated evidence | Residual risk (as of 2026-07-23) |
|-----------|----------------|-----------------------------------|
| **Architecture** | `nix flake check path:. --no-build` evaluates every aspect/host combination; `modules/parts/service-aspect-invariants.nix` (added by task M1) proves `backup.nix`/`observability.nix` carry no Soyo-specific hardcoded values against a fixture host. | Before M1, both aspects silently hardcoded Soyo's NAS hostname, SSH user, and LAN NIC — a reusability defect that would have silently miscompiled on a differently-configured host. Fixed; no known open architecture defect. |
| **Critical path (Soyo)** | DNS/DHCP split ownership and TPM PCR binding are VM-verified by the four KVM checks (§4.2). Task C1 (2026-07-23) fixed `tailscale-auth` ordering against a nonexistent `tailscale.service` unit (now orders against `tailscaled.service`, verified by a positive/negative fixture in `systemd-hardening-checks.nix`). | TPM re-enrollment after a real PCR change remains untested outside a manual drill (`recovery.md`) — unchanged by this plan. A single Soyo appliance has no hardware redundancy; a second appliance is an intentional deferral (see [canonical design](../superpowers/specs/soyo-dns-dhcp-appliance.md#m4--expansion)), not a defect. |
| **Workstation (zbook)** | NVIDIA/suspend fixes remain documented and unchanged by this plan (§3.1). | Nixpkgs-unstable channel drift risk unchanged (§6.1). |
| **Secrets management** | agenix-rekey two-layer flow unchanged. Task R1 (2026-07-23) found and fixed a role-separation defect: Soyo (an LAN appliance with no development role) received a GitHub token and workstation/agent tooling via the shared Home Manager base; that credential surface is now isolated to workstation hosts. | Single-operator bus factor and master-key-compromise risk are unchanged (§6.1) — accepted, not newly discovered. |
| **Testing pyramid** | Four KVM checks — `dns-dhcp-vm`, `backup-unit-vm`, `impermanence-vm`, `clipboard-protocols` — plus static/evaluation/unit tiers (§4). Task C4 (2026-07-23) fixed `clipboard-protocols`' nondeterministic PRIMARY-selection race (two concurrent `wl-copy` processes racing on `wlroots`' data-control handling) and added it to the enforced KVM set; `modules/parts/kvm-gate-drift-check.nix` now proves the four-check set can't silently drift from `ci.yml`/`just test-resilience`. | **Not fixed — open, requires separate authorization:** re-verified 2026-07-23 (task S2), GitHub ruleset `18830833` has **no `required_status_checks` rule**, so none of these checks — or any other CI job — currently blocks a merge to `main`. See [`docs/security/github-settings.md`](../security/github-settings.md#required-status-checks) for the full finding and the recommended (not-yet-applied) fix. |
| **Documentation** | This 2026-07-23 pass reconciled `docs/status.json` lifecycle metadata, `docs/README.md` discoverability, and this document against actual evaluated/tested state; `checks.docs-correctness` (`modules/parts/docs-checks.nix`) verifies links, anchors, lifecycle status, and discoverability mechanically. | Documentation drift is only checked mechanically for links/anchors/lifecycle, not for factual accuracy — this kind of narrative reconciliation is manual and periodic, not continuously enforced. |
| **Operational maturity** | Tasks O1–O3 (2026-07-23) completed operational failure-alert coverage (`OnFailure=ntfy-failure@` wired onto all reviewed units plus a new `smartd` notification hook), bounded retained Limine boot generations, and made the healthcheck prove backup freshness and every probe, not just service-active state. | **Not fixed — open, requires separate human triage:** `osv-scanner` (added by task S3) found a real high-severity finding, `@opentelemetry/propagator-jaeger@2.8.0` (GHSA-45rx-2jwx-cxfr, fixed upstream in 2.9.0), in the vendored `command-code` npm dependency tree. See [`docs/security/supply-chain.md`](../security/supply-chain.md#override-ownership-and-lifecycle). |

Deliberate, accepted-risk deferrals — not defects, and not tracked as open
gaps — are recorded in the canonical design's
[M4 — Expansion](../superpowers/specs/soyo-dns-dhcp-appliance.md#m4--expansion)
section: full dual-stack IPv6 DNS/DHCP, RAID1 (contingent on a second disk
slot), off-site NAS replication, M4 guest applications (e.g. Jellyfin), and a
second DNS/DHCP appliance for redundancy.

**Bottom line:** Soyo and zbook are deployed and production-hardened per the
dated evidence above. Macbook and ubuntu have real host assemblers, complete
install runbooks (`docs/install-macbook.md`, `docs/install-ubuntu.md`), and
CI-verified evaluation and build coverage (`build-macbook`, `build-ubuntu`
jobs in `ci.yml`) as of 2026-07-23 — hardware deployment is what remains, not
configuration or CI coverage (see §7 for the genuinely still-open pieces:
darwin-native `ssh`/`tailscale`/`backup` aspects and `dendritic-options` test
coverage for macbook/ubuntu).

---

## 1. Architecture Assessment

### 1.1 Dendritic Pattern (flake-parts + import-tree)

**Strengths:**
- Zero-registry aspect registration: drop a `.nix` under `modules/nixos/`, `modules/home/`, or `modules/darwin/` → available as `aspects.nixos.<name>`
- Host assemblers (`modules/parts/soyo.nix`, `zbook.nix`) explicitly opt in via `with config.aspects.nixos; [ ... ]` — no implicit coupling
- `_`-prefixed paths (`modules/_pkgs/`) excluded from auto-import — clean separation of `callPackage` helpers

**Risks:**
- Option namespace collisions if two aspects define `lanAppliance.services.<same>` — mitigated by `dendritic-options` check in flake
- New contributors may not realize aspects are **not enabled by default** — documented in AGENTS.md and learning path

### 1.2 Host Structure

```text
hosts/<name>/
  ├── facter.json          # Hardware facts (nixos-facter) — NEVER hand-edit
  ├── disko.nix            # Disk layout (NixOS only)
  ├── boot.nix             # Kernel, loader, initrd, LUKS/TPM
  ├── networking.nix       # Interfaces, firewall, Tailscale config
  ├── users.nix            # User accounts, password hashes (agenix refs)
  ├── persistence.nix      # preservation paths (impermanence)
  ├── topology.nix         # nix-topology node data
  └── *.nix                # Host-specific service config (dns.nix, dhcp.nix, nvidia.nix, etc.)
```

**Assessment:** Clean separation. Host directories are data + policy only; reusable logic lives in aspects. Adding a new host = copy `hosts/soyo/` skeleton, swap `facter.json`, adjust aspects.

### 1.3 Aspect Namespaces

| Namespace | Modules | Consumers |
|-----------|---------|-----------|
| `aspects.nixos.*` | `modules/nixos/*.nix` | NixOS host assemblers |
| `aspects.darwin.*` | `modules/darwin/*.nix` | macOS host assemblers |
| `aspects.homeManager.*` | `modules/home/*.nix` | All hosts (NixOS, darwin, standalone HM) |

**Invariant (AGENTS.md #3):** `base.nix` and `home/base.nix` stay role-neutral — no network backend, swap policy, or GUI assumptions. Role-specific config in `server.nix`, `workstation.nix`, `desktop.nix`, `laptop.nix`.

---

## 2. Critical Path: Soyo LAN Appliance

### 2.1 DNS/DHCP Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT REQUEST                            │
└─────────────────────────────┬───────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              ▼                               ▼
       Blocky (53)                      dnsmasq (5353)
    Forward A/AAAA                    Reverse PTR (lease-aware)
    DoH upstream                      reservations.nix
    Ad-blocking                       DHCP leases → PTR
              │                               │
              └───────────────┬───────────────┘
                              ▼
                    systemd-resolved (split DNS)
                   .home.arpa → Blocky
                   *.ts.net → Tailscale
```

**Single source of truth:** `hosts/soyo/reservations.nix` → validates via `lib/network/validate-reservations.nix` → drives both Blocky (forward) and dnsmasq (reverse + DHCP).

**VM test coverage (`dns-dhcp-vm`):**
- Forward resolution (Blocky)
- Reverse resolution (dnsmasq lease-aware PTR)
- DHCP lease lifecycle (acquire, renew, expire, re-acquire)
- Outage resilience (Blocky down → dnsmasq still serves PTR; dnsmasq down → Blocky still serves forward)
- Service isolation (MemoryMax/CPUQuota on both)

### 2.2 Impermanence & Persistence

| Path | Persisted? | Mechanism | Rationale |
|------|------------|-----------|-----------|
| `/` (root) | ❌ | Btrfs snapshot rollback to `root-blank` each boot (initrd `rollback-root`) | Clean state, no config drift |
| `/nix` | ✅ | Separate subvolume | Store survives rollback |
| `/persist` | ✅ | Separate subvolume, `neededForBoot=true` | SSH host keys, machine-id, service state, sbctl keys |
| `/snapshots` | ✅ | Separate subvolume | btrbk local snapshots |
| `/var/lib/nixos` | ✅ | preservation | Declarative UID/GID stability |
| `/etc/ssh` | ✅ | preservation (in initrd) | Agenix host key for secret decryption |
| `/var/lib/dnsmasq` | ✅ | preservation | DHCP lease DB survives reboot |
| `/var/lib/{prometheus,loki,grafana,tempo,alloy}` | ✅ | preservation | Metrics/logs/traces continuity |

**Tested by:** `impermanence-vm` (missing `neededForBoot` → assertion failure; correct config → passes)

### 2.3 TPM2 Auto-Unlock + Secure Boot

| Phase | PCRs | Secure Boot | Status |
|-------|------|-------------|--------|
| 1 | 7 (Secure Boot state) | ❌ Off | ✅ Production |
| 2 | 0 (UEFI) + 2 (UEFI CA) + 7 | ✅ On | ✅ Enrolled, untested after PCR change |

**Recovery paths (all documented in `recovery.md`):**
1. **TPM auto-unlock** (primary) — `crypttab: tpm2-device=auto`
2. **Passphrase** (break-glass) — retained keyslot
3. **Initrd SSH** (port 2222, LAN) — `ssh -p 2222 root@soyo`
4. **Direct-link rescue** (192.168.254.0/30, physical) — `ssh root@192.168.254.2`

**Critical invariant (AGENTS.md #7):** Never bind PCR 8 (kernel) or 9 (initrd/store) — breaks unattended unlock.

### 2.4 Secrets (agenix-rekey)

```text
secrets/
├── *.age                    # Master-encrypted (operator key)
└── rekeyed/<host>/
    └── *-*.age              # Host-rekeyed (SSH host key) — AUTO-GENERATED
```

**Flow:**
1. `agenix edit secrets/foo.age` → encrypts with master key (`/etc/agenix-rekey/master-identity` = operator SSH key)
2. Host assembler declares `age.secrets.foo.rekeyFile = ../../secrets/foo.age`
3. `agenix rekey` → decrypts with master, re-encrypts with host pubkey (`secrets/soyo.pub` → SSH host key), writes to `secrets/rekeyed/soyo/foo-age.age`
4. Activation: `agenix-activation` decrypts host-rekeyed file → `/run/agenix/foo`

**Recovery drill:** `just recover-secrets --dry-run` → `just recover-secrets --yes` (script in `scripts/recover-secrets.sh`)

---

## 3. Workstation: zbook (HP ZBook Studio 16 G10, RTX 4000 Ada)

### 3.1 Fixed Hardware Issues (Documented in AGENTS.md)

| Issue | Root Cause | Fix | Location |
|-------|------------|-----|----------|
| Nouveau on first boot | `services.xserver.videoDrivers = ["nvidia"]` needs reboot | Document: rebuild → reboot | `hosts/zbook/INSTALL.md` |
| No deep S3 suspend | HP firmware routes wake to S0ix only | Use s2idle; `mem_sleep_default=deep` removed | `hosts/zbook/boot.nix` |
| Logitech receiver stutter | powertop autosuspends Unifying/Bolt | `usbcore.quirks=046d:c52b:b,046d:c532:b` | `modules/nixos/laptop.nix` |
| NVIDIA GSP Xid 120 on resume | RISC-V firmware crash across 570–610+ | `NVreg_EnableGpuFirmware=0` | `modules/nixos/nvidia.nix` |
| Dock RTL8153 immediate wake | Link-state change on s2idle entry | udev rule disables wake | `modules/nixos/laptop.nix` |
| Thunderbolt dock wake | TDM0/TDM1 fire on suspend entry | systemd service disables via `/proc/acpi/wakeup` | `modules/nixos/laptop.nix` |
| DMS auto-suspend during media | `acSuspendTimeout: 600` ignores audio | `media-sleep-inhibit` user service (MPRIS polling) | `modules/home/sway.nix` |
| NM "connected" but no net after s2idle | Data path broken on USB-C dock Ethernet | `resumeCommands: nmcli connection reload + resolvectl flush-caches` | `modules/nixos/laptop.nix` |

### 3.2 Desktop Stack

- **Compositor:** Sway + DMS (Dank Material Shell) + kanshi (output config)
- **Apps:** dcal, dsearch, dms-plugins via flake inputs
- **GPU:** PRIME offload (Intel render, NVIDIA on-demand) — sync mode optional for gaming
- **User services:** atuin, starship, zsh, neovim (lazy.nvim), tmux, yazi, lazygit

---

## 4. Testing & Verification Maturity

### 4.1 Test Pyramid Implementation

```text
                        ┌─────────────────────┐
                        │  MANUAL DRILLS      │  ← Reboot, TPM unlock, break-glass,
                        │  (Documented only)  │     initrd SSH, direct-link, DHCP client,
                        └─────────┬───────────┘     restic restore, tampered boot, re-enroll
                                  │
              ┌───────────────────┼───────────────────┐
              ▼                   ▼                   ▼
       ┌───────────┐       ┌───────────────┐   ┌──────────────┐
       │ ON-HOST   │       │ KVM VM TESTS  │   │ UNIT TESTS   │
       │ HEALTHCHECK│       │ (nixosTest)   │   │ (shell/py)   │
       └─────┬─────┘       └───────┬───────┘   └──────┬───────┘
             │                     │                  │
             ▼                     ▼                  ▼
       ┌─────────────────────────────────────────────────────┐
       │           EVALUATION CHECKS (nix flake check)       │
       │  formatting • deadnix • statix • typos • dendritic  │
       │  option checks • gitleaks • all outputs build       │
       └─────────────────────────────────────────────────────┘
```

### 4.2 KVM Tests (Run via `just test-resilience`)

| Test | Duration | Validates |
|------|----------|-----------|
| `dns-dhcp-vm` | ~6 min | DNS forward/reverse, DHCP lease lifecycle, outage resilience, service isolation |
| `backup-unit-vm` | ~3 min | restic backup success/failure metrics, OnFailure handoff, wrong password → metric 0 |
| `impermanence-vm` | ~2 min | `/persist.neededForBoot` assertion, root rollback to blank snapshot |
| `clipboard-protocols` | ~2 min | Wayland regular/PRIMARY clipboard selection independence (data-control protocol); fixed 2026-07-23 (task C4) — was flaky before, now deterministic and enforced |

**All four run in `ci.yml`'s `resilience` job and `just test-resilience`**
(`modules/parts/kvm-gate-drift-check.nix` proves this list can't silently
drift). This is a CI job outcome, not yet a branch-protection merge gate: as
of 2026-07-23 (task S2), GitHub ruleset `18830833` has no
`required_status_checks` rule, so a pull request can merge to `main`
regardless of whether this job — or any other CI job — passed. See
[`docs/security/github-settings.md`](../security/github-settings.md#required-status-checks)
for the open finding and its not-yet-applied recommended fix.

### 4.3 On-Host Healthcheck (`just healthcheck <host>`)

Checks (auto-detected role + NIC):
- Network: NIC up, hostname, root SSH blocked
- Services: role-appropriate units active (Blocky/dnsmasq/Prometheus stack on appliance; greetd on workstation)
- Timers: nix-store-optimise, btrbk, fstrim enabled
- Secrets: agenix decrypted (`/run/agenix/` non-empty)
- System: journald persistent, Tailscale connected, SMART running
- Secure Boot: enabled + sbctl keys in `/persist`
- Appliance-only: DNS resolution (forward/reverse/ad-block), DHCP lease file, observability stack metrics, blackbox probes

### 4.4 Manual-Only Gates (Cannot Automate)

| Drill | Why Manual | Documented In |
|-------|------------|---------------|
| TPM auto-unlock | Requires cold reboot | `recovery.md` |
| Break-glass passphrase | Destructive (wipe TPM slot) | `recovery.md` |
| Initrd SSH unlock | Requires reboot + network access | `recovery.md` |
| Direct-link rescue | Physical cable + static IP | `recovery.md` |
| DHCP client receives DNS/search | Requires client machine | `router-recommendation.md` |
| Forced unit failure → ntfy | Requires triggering real failure | `backup-and-restore.md` |
| Restic restore drill | Destructive, time-consuming | `backup-and-restore.md` |
| Tampered boot fails checksum | Secure Boot verification | `recovery.md` |
| TPM re-enrollment after PCR change | Requires PCR change + reboot | `recovery.md` |

---

## 5. Operational Workflows

### 5.1 Daily Commands

| Task | Command |
|------|---------|
| Format code | `just fmt` |
| Lint (full tree) | `just lint` |
| Full flake check | `just check` |
| Build host | `just build soyo` |
| Deploy (auto local/remote) | `just deploy soyo` |
| Healthcheck | `just healthcheck soyo` |
| Rekey secrets | `just rekey` |
| Update topology SVG | `just topology` |
| Dev shell | `just dev` |

### 5.2 Deployment Model

- **Local:** `sudo nixos-rebuild switch --flake .#<host>`
- **Remote:** `deploy .#<host>` (deploy-rs — checks, magic rollback)
- **Fallback:** `nixos-rebuild --target-host` (native SSH deploy)

### 5.3 Update Workflow

1. `nix flake update <input>` (or `nix flake update` for all)
2. `just check` (builds + VM tests)
3. `just deploy <host>`
4. `just healthcheck <host>`
5. Commit `flake.lock` + any config changes

---

## 6. Risk Register & Technical Debt

### 6.1 High-Risk Items

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **NixOS unstable breaks zbook** | Medium | Workstation unusable | Pin `nixpkgs-unstable` in flake.lock; `just check` catches eval failures; rollback via `nixos-rebuild switch --flake .#zbook --rollback` |
| **TPM PCR 0+2+7 binding fails after kernel/UEFI update** | Medium | Auto-unlock breaks, manual unlock required | Documented re-enrollment procedure; passphrase fallback always retained |
| **restic repository corruption** | Low | Backup loss | `restic check --read-data` in VM test; weekly check timer; NAS-side snapshots |
| **agenix master key compromise** | Low | All secrets exposed | Master key = operator SSH key (hardware-backed, e.g., YubiKey); rotation procedure in `secrets.md` |
| **Single-person bus factor** | High | Knowledge loss | All procedures documented; learning path teaches architecture |
| **No CI required-status-checks gate on `main`** (open, verified 2026-07-23, task S2) | Certain — confirmed present today | A merge to `main` is not blocked by a failing static, evaluation, build, or KVM job | GitHub ruleset `18830833` has no `required_status_checks` rule (re-read 2026-07-23; a classic branch-protection record doesn't exist either). Fix requires a repository-administrator ruleset change under separate, explicit authorization (see `G2` in the remediation plan) — not yet applied. Details: [`docs/security/github-settings.md`](../security/github-settings.md#required-status-checks). |
| **Open `@opentelemetry/propagator-jaeger` CVE** (open, found 2026-07-23, task S3) | Confirmed present in the vendored `command-code` dependency tree | High-severity per GHSA-45rx-2jwx-cxfr | `osv-scanner`'s new scheduled scan (`security-scan.yml`) found `@opentelemetry/propagator-jaeger@2.8.0`, fixed upstream in 2.9.0. Left for human triage (add an override entry and re-run `just update-command-code`, or confirm the code path isn't exercised) rather than fixed silently. Details: [`docs/security/supply-chain.md`](../security/supply-chain.md#override-ownership-and-lifecycle). |

### 6.2 Technical Debt / Improvement Opportunities

| Area | Description | Effort |
|------|-------------|--------|
| **Macbook/Ubuntu hosts** | Assembler, CI evaluation/build, and install runbooks complete (verified 2026-07-23); hardware deploy still pending, plus the genuinely open darwin-native aspect and `dendritic-options` coverage gaps in §7 | Low (hardware access) / Medium (darwin aspects) |
| **Backup restore automation** | Currently manual drill only; could schedule quarterly automated test | Low |
| **Topology diagram automation** | Public overview updated manually via `just topology`; could be CI artifact | Low |
| **Secrets rotation schedule** | No enforced rotation; rely on manual `just rekey` | Low |
| **Observability alerting scope** | Grafana already routes Blocky-down, dnsmasq-down, backup-failure, and Btrfs-space alerts through ntfy (`lib/observability/grafana-alert-setup.nix`, verified 2026-07-23) — not a gap. Still missing: Prometheus scrape-failure, Loki ingestion-lag, and Tempo trace-drop alerts, and an SLI/SLO dashboard (see §7 Phase 2) | Medium |
| **NixOS version pinning** | Soyo on 26.05, zbook on unstable — consider aligning or documenting divergence | Low |

---

## 7. Recommendations for Next Phases

### Phase 1: Macbook + Ubuntu Hosts (M4 Expansion) — partially complete as of 2026-07-23

**Done** (verified against the repository on 2026-07-23):

- `hosts/macbook/` exists (`users.nix`, `INSTALL.md`); `modules/parts/macbook.nix`
  assembles `darwinConfigurations.macbook` on `aarch64-darwin`, selecting
  `aspects.darwin.base` plus the shared `aspects.homeManager.{base,development,
  desktop,ssh,aerospace}`.
- `modules/parts/ubuntu.nix` assembles `homeConfigurations.ubuntu` via
  `inputs.home-manager.lib.homeManagerConfiguration`, setting
  `home.username`/`home.homeDirectory` explicitly. `hosts/ubuntu/` deliberately
  does not exist — `AGENTS.md` documents that standalone HM hosts don't need a
  `hosts/<name>/` directory.
- CI builds both: `ci.yml`'s `build-macbook` job (`macos-latest`, builds
  `darwinConfigurations.macbook.config.system.build.toplevel`) and
  `build-ubuntu` job (builds `homeConfigurations.ubuntu.activationPackage`);
  `checks.macbook-desktop-invariants` and `checks.ubuntu-desktop-invariants`
  run in the evaluation tier.
- `just deploy macbook`/`just deploy ubuntu` and `just build-macbook`/
  `just build-ubuntu` exist and dispatch to `darwin-rebuild switch` and
  `home-manager switch`, respectively.
- Install runbooks are complete: [`docs/install-macbook.md`](../install-macbook.md),
  [`docs/install-ubuntu.md`](../install-ubuntu.md). Tasks H1/H2 (2026-07-23)
  corrected desktop-binding and tool-availability contract mismatches (e.g.
  macbook's terminal is `Terminal.app`, not the Linux-only Ghostty package;
  ubuntu has no automatic Sway session registration) — see
  [`docs/workstation-setup.md`](../workstation-setup.md).

**Still genuinely open** (not addressed by this remediation plan — out of its
scope):

- `modules/darwin/` has only `base.nix`. There is no darwin-native `ssh.nix`,
  `tailscale.nix`, `backup.nix`, or `maintenance.nix` mirroring the NixOS
  aspects soyo/zbook get; macbook would deploy today without those system-level
  aspects (see the frozen
  [`repository-gaps-and-improvements.md`](../superpowers/specs/repository-gaps-and-improvements.md)'s
  H1 finding, still accurate).
- `dendritic-options` in `modules/parts/perSystem.nix` only computes `hostOpts`
  for `soyo`/`zbook`; macbook (`aspects.darwin.*`) and ubuntu
  (`aspects.homeManager.*`) have no equivalent namespace-coverage assertion.
- Hardware validation itself — first `darwin-rebuild switch`, first
  `home-manager switch --flake .#ubuntu`, and confirming the documented login
  shell/terminal/desktop-session/application matrix on real hardware — is
  deliberately deferred to `G2` in the remediation plan (separately authorized
  live validation), not a repository defect.

### Phase 2: Observability Hardening

- Add ntfy alerts for: Prometheus scrape failures, Loki ingestion lag, Tempo trace drops
- Implement alert routing (critical → immediate ntfy; warning → daily digest)
- Add SLI/SLO dashboard for DNS/DHCP availability

### Phase 3: Supply Chain Hardening

- Enable `git-hooks.nix` signed commits verification
- Add `nixpkgs` input signature verification (when available)
- Document SBOM generation for host closures

### Phase 4: Multi-User / Team Readiness

- Add non-admin user aspect (restricted sudo, no SSH key deployment)
- Implement per-user Home Manager profiles
- Add shared secret namespace (team passwords, API keys)

---

## 8. Quick Reference: File-to-Concept Map

| Concept | Primary Files |
|---------|---------------|
| Flake entry + dendritic import | `flake.nix` |
| Aspect option namespace | `modules/parts/aspect-options.nix` |
| Soyo assembler | `modules/parts/soyo.nix` |
| Zbook assembler | `modules/parts/zbook.nix` |
| DNS/DHCP split ownership | `modules/nixos/blocky.nix`, `modules/nixos/dhcp.nix`, `hosts/soyo/reservations.nix` |
| Impermanence rollback-root | `modules/nixos/persistence.nix` (initrd service) |
| TPM PCR binding | `hosts/soyo/boot.nix`, `hosts/soyo/initrd-unlock.nix` |
| agenix-rekey flow | `modules/nixos/users.nix`, `scripts/recover-secrets.sh`, `docs/secrets.md` |
| Backup (restic + btrbk) | `modules/nixos/backup.nix`, `hosts/*/backup.nix` |
| KVM tests | `modules/parts/dns-dhcp-vm-check.nix`, `modules/parts/backup-integration-check.nix`, `modules/parts/impermanence-vm-check.nix`, `modules/parts/clipboard-protocol-check.nix` |
| Healthcheck | `scripts/healthcheck.sh`, `modules/parts/perSystem.nix` |
| Systemd hardening | `lib/systemd-hardening.nix` |
| Network validation | `lib/network/validate-reservations.nix` |

---

*Last updated: 2026-07-23 (task D1, [repository assessment remediation plan](../superpowers/plans/2026-07-23-repository-assessment-remediation.md)) — reconciled every claim above against the repository's evaluated/tested state, replaced unqualified ratings with dated evidence, and recorded the two findings this plan surfaced but did not fix (missing `required_status_checks` ruleset rule; open `@opentelemetry/propagator-jaeger` CVE). This assessment should be reviewed after each milestone (M1–M4), after each future remediation plan, and before major architectural changes.*
