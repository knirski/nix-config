# srvos hardening cross-check

**Lifecycle: active.** Review of the Soyo appliance configuration against the
opinionated server hardening of [nix-community/srvos](https://github.com/nix-community/srvos),
performed 2026-08-13.

## Method

Compared the srvos server role and common profiles
(`nixos/server/default.nix`, `nixos/common/{default,networking,nix,openssh,sudo}.nix`,
`shared/server.nix`) at `main` @ `fb298f6a85da3241b2d024e82b618ab3f5cc6de2`
(2026-08-13) against the soyo assembler and its aspects. srvos is a reference,
not a dependency: this repository keeps `base.nix` role-neutral and maintains
its own invariants (AGENTS.md), so items are adopted only when they fit that
design. Re-run this comparison periodically — srvos moves.

## Applied 2026-08-13

| Item | srvos source | Where |
| --- | --- | --- |
| Hardware watchdog (`RuntimeWatchdogSec=15s`, `RebootWatchdogSec=30s`) | `nixos/server/default.nix` | `modules/nixos/server.nix`; `iTCO_wdt` loaded in the initrd via `hosts/soyo/boot.nix` (see rationale below) |
| Sleep off (`AllowSuspend`/`AllowHibernation = "no"`) | `nixos/server/default.nix` | `modules/nixos/server.nix` |
| No emergency mode (`enableEmergencyMode = false`) | `nixos/server/default.nix` | `modules/nixos/server.nix` |
| LLMNR off in systemd-resolved | `nixos/common/networking.nix` | `modules/nixos/blocky.nix` |
| `security.sudo.execWheelOnly = true` | `nixos/common/sudo.nix` | `modules/nixos/users.nix` |
| nix-daemon `OOMScoreAdjust=250` + batch CPU / idle IO scheduling | `nixos/common/nix.nix` | `modules/nixos/server.nix` |

Rationale, per item:

- **Watchdog** — AGENTS.md documents a 2026-08-11 total hang (ksoftirqd stuck
  in the rpfilter match) that required a manual cold restart. A hardware
  watchdog would have rebooted the box in ~15 s. Requires `/dev/watchdog`
  (iTCO_wdt on the N150). The module is loaded in the **initrd** (`hosts/soyo/boot.nix`):
  `boot.kernelModules` renders into `/etc/modules-load.d/nixos.conf`, which
  `systemd-modules-load.service` reads only after PID1 has already tried to
  arm the watchdog at startup, so the arm would fail silently. From the
  initrd, `/dev/watchdog` already exists on devtmpfs when stage-2 systemd
  starts. See Manual verification below.
- **Sleep off** — an appliance that suspends takes DNS/DHCP offline until
  someone physically wakes it.
- **No emergency mode** — the emergency shell sits on a console nobody can
  reach; boot-generations fallback is the recovery path.
- **LLMNR off** — LLMNR is a fallback resolution path and is spoofable on the
  LAN. DHCP already hands clients Blocky as the only resolver, so disabling
  it costs nothing.
- **execWheelOnly** — non-wheel users cannot execute sudo at all
  (CVE-2021-3156 class). Soyo has one login user, in wheel; zero functional
  impact.
- **nix-daemon pressure** — remote builds (`nixos-rebuild --target-host`) run
  on soyo. OOMScoreAdjust makes builds the kernel OOM killer's first victims;
  batch/idle scheduling keeps them from starving blocky/dnsmasq. Complements
  the guest-service limits of invariant 2; earlyoom remains the first line.

## Already covered before this review

| srvos item | Equivalent already in place |
| --- | --- |
| `PasswordAuthentication`/`KbdInteractiveAuthentication` off, `PermitRootLogin` off | `modules/nixos/ssh.nix` |
| `networking.useNetworkd`, wait-online disabled | `modules/nixos/server.nix` |
| `networking.firewall.enable` | `hosts/soyo/networking.nix` (nftables backend) |
| `allowPing = true` | NixOS default; blackbox ICMP probes rely on it |
| `users.mutableUsers = false` | `modules/nixos/users.nix` |
| `wheelNeedsPassword = false` | `modules/nixos/users.nix` |
| Boot entries bounded | `limine.maxGenerations = 10` in `hosts/soyo/boot.nix` (srvos uses `configurationLimit = 5`; same mechanism, deliberate value) |
| `nix.optimise.automatic` | Deliberately replaced by the weekly bounded `nix-store-optimise` timer in `modules/nixos/base.nix` (documented there) |
| `services.userborn` | srvos itself disables userborn when it detects impermanence; this repo uses preservation, same rationale |

## Deliberate deviations (keep)

- **Documentation enabled** — srvos disables `documentation.nixos.enable` by
  default on servers; this repo deliberately enables it (learning mission,
  `modules/nixos/base.nix`).
- **Timezone** — srvos defaults to UTC; this repo uses `Europe/Warsaw`.
- **`KExecWatchdogSec`** (srvos sets `1m`) — omitted; NixOS does not use kexec
  here, so the kexec hang it guards against cannot occur.

## Considered, not applied

| Item | Reason |
| --- | --- |
| System-level SSH `authorizedKeysFiles` (drop `%h/.ssh/authorized_keys`) | Opinionated: prevents a compromised account from adding persistent keys, but changes the documented key flow (`docs/secrets.md`). Revisit if the threat model changes |
| `services.openssh.settings.UseDns = false` | Reverse lookups hit Blocky locally (fast); marginal |
| `networking.firewall.logRefusedConnections = false` | Journal noise reduction only; LAN exposure is limited |
| `systemd-networkd`/`resolved` `stopIfChanged = false` | Avoids a network restart during `nixos-rebuild switch`; small DNS-blip avoidance, revisit on next appliance-uptime review |
| Server micro-cleanups (fonts/xdg/command-not-found off, `stub-ld`/`ldso32`, `gitMinimal`) | Small store/RAM savings only; would live in the server aspect if adopted |
| `services.userborn` | srvos skips under impermanence; this repo uses preservation (see above) |

## Manual verification (required)

- **Watchdog armed:** after the next soyo deploy + reboot, run `wdctl` on soyo
  — it must report the watchdog device and timeout. If no device appears,
  check `dmesg | grep -i watchdog` / `journalctl -b | grep -i watchdog`; do
  **not** treat the config as protecting the box until this passes. (The
  systemd option is harmless without a device — it only logs — which is why
  the check is on us.)
- **Sleep disabled:** `systemctl suspend` must exit non-zero and leave the
  system running. The exact logind message varies by systemd version (e.g.
  `Call to Suspend failed: Sleep verb 'suspend' is disabled by config`) —
  treat it as illustrative, not as the pass condition.
- **Emergency mode:** the config change is verified by a successful normal
  boot; the failure path (boot error → continue instead of emergency shell)
  is covered by the existing boot-generation fallback drills.

## References

- srvos repository: <https://github.com/nix-community/srvos>
- Reviewed files at `main` @ `fb298f6a85da3241b2d024e82b618ab3f5cc6de2`:
  `nixos/server/default.nix`, `nixos/common/*.nix`, `shared/server.nix`
- Related: [Service hardening policy](service-hardening.md),
  [Recovery](../recovery.md)
