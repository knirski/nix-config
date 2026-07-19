# Project Assessment — nix-config Multi-Host Flake

*Comprehensive architectural and operational review. Written for maintainers and contributors to understand current state, risks, and prioritized next steps.*

---

## Executive Summary

This is a **production-grade, learning-oriented NixOS/nix-darwin flake** managing four hosts across two roles (LAN appliance + workstations). The codebase demonstrates:

| Dimension | Rating | Evidence |
|-----------|--------|----------|
| **Architecture** | ★★★★★ | Dendritic pattern, thin hosts, reusable aspects, declarative recovery |
| **Critical path (Soyo)** | ★★★★★ | DNS/DHCP split ownership, TPM PCR binding, multiple recovery paths, VM-verified |
| **Workstation (zbook)** | ★★★★☆ | NVIDIA/suspend fixes documented, DMS integrated, gaming-ready |
| **Secrets management** | ★★★★★ | agenix-rekey two-layer flow, master/host key separation, recovery drill scripted |
| **Testing pyramid** | ★★★★★ | Static → evaluation → unit → KVM VM → on-host healthcheck → manual drills |
| **Documentation** | ★★★★★ | Canonical design doc, beginner secrets guide, learning path, runbooks |
| **Operational maturity** | ★★★★☆ | `just` workflows, deploy-rs, healthchecks, topology diagrams, manual-only gates documented |

**Bottom line:** Soyo is production-hardened. Zbook is daily-driver stable. Macbook/Ubuntu hosts are planned but untested — the next phase of work.

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

**All three must pass before merge.** CI runs them on PRs.

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

### 6.2 Technical Debt / Improvement Opportunities

| Area | Description | Effort |
|------|-------------|--------|
| **Macbook/Ubuntu hosts** | Planned but untested — need hardware-specific iteration | Medium |
| **Backup restore automation** | Currently manual drill only; could schedule quarterly automated test | Low |
| **Topology diagram automation** | Public overview updated manually via `just topology`; could be CI artifact | Low |
| **Secrets rotation schedule** | No enforced rotation; rely on manual `just rekey` | Low |
| **Observability alerting** | Grafana alerts configured but no ntfy integration for critical metrics | Medium |
| **NixOS version pinning** | Soyo on 26.05, zbook on unstable — consider aligning or documenting divergence | Low |

---

## 7. Recommendations for Next Phases

### Phase 1: Macbook + Ubuntu Hosts (M4 Expansion)

1. **Macbook (nix-darwin):**
   - Copy `hosts/soyo/` → `hosts/macbook/` skeleton
   - Adapt `disko.nix` → skip (APFS native)
   - Adapt `boot.nix` → skip (no initrd/LUKS/TPM)
   - Select darwin aspects: `base`, `desktop`, `ssh`, `tailscale`, `users`, `backup`, `maintenance`
   - Add darwin-specific: `aerospace.nix` (tiling WM), home-manager integration

2. **Ubuntu (standalone HM):**
   - Use `inputs.home-manager.lib.homeManagerConfiguration`
   - Only HM aspects apply (no `aspects.nixos.*` or `aspects.darwin.*`)
   - Set `home.username`, `home.homeDirectory` explicitly
   - Activate: `home-manager switch --flake .#ubuntu`

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
| KVM tests | `modules/parts/dns-dhcp-vm-check.nix`, `modules/parts/backup-integration-check.nix`, `modules/parts/impermanence-vm-check.nix` |
| Healthcheck | `scripts/healthcheck.sh`, `modules/parts/perSystem.nix` |
| Systemd hardening | `lib/systemd-hardening.nix` |
| Network validation | `lib/network/validate-reservations.nix` |

---

*Last updated: 2026-07-19. This assessment should be reviewed after each milestone (M1–M4) and before major architectural changes.*
