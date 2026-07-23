# Service hardening policy

**Lifecycle: active.** This records the reviewed privilege, write and network
requirements for repository-owned systemd units. It complements resource
limits; neither mechanism proves immunity to every resource-exhaustion event.

## Failure notification classes

Four distinct mechanisms exist for "something is wrong"; they overlap in
purpose but not in trigger, transport, or failure mode. Confusing them (e.g.
treating a threshold alert as proof a unit didn't crash) hides real gaps:

| Class | Trigger | Transport | Covers | Cannot cover |
| --- | --- | --- | --- | --- |
| Threshold alert | A Prometheus expression crosses a bound (e.g. `soyo_disk_space_low`) | Grafana → its `ntfy` contact point, provisioned by `grafana-alert-setup` | Gradual, measurable drift (disk filling, backup metric stale) | A unit that never ran, or a metric pipeline itself down |
| Unit execution failure | Any reviewed unit's `systemd` job exits non-zero or times out | `OnFailure=ntfy-failure@%N.service` → the shared `ntfy-failure@` template | The reviewed units in `checks.failure-notification-invariants` (Btrfs scrub, `nix-gc`, free-space check, restic, btrbk, `grafana-alert-setup`, `nix-store-optimise`) crashing outright, even before any metric would reflect it | Units outside the reviewed list; a fully hung (not failed) unit |
| SMART warning | `smartd` self-test/attribute failure on a monitored disk | `smartd`'s `-M exec` hook → `ntfy-smartd-notify` (see `modules/nixos/maintenance.nix`) | Disk-level hardware degradation, independent of any systemd unit | Data loss already in progress; this is an early-warning signal only |
| Total host outage | Soyo is unreachable at all (panic, dead PSU, hung kernel) | The Synology's Uptime Kuma, probing from an independent failure domain | The one case none of the above can self-report — a dead box can't push its own notification | Everything above; Uptime Kuma only proves liveness, not that a specific job succeeded |

The first three are all "the box is alive and something failed" — see
`docs/superpowers/specs/soyo-dns-dhcp-appliance.md`, "Health Checking", for
why total host outage necessarily needs an external, independently-powered
watcher instead. That NAS-side Uptime Kuma setup is an operator step, not
flake-managed, and is not re-documented here.

`OnFailure=` is deliberately a reviewed allowlist of specific units (enforced
by `checks.failure-notification-invariants`), not a blanket systemd drop-in
applied to every unit on the host: a global drop-in would also fire for
irrelevant transient units and — without the same self-guard `ntfy-failure@`
uses — risks recursing on its own failure.

## Review method

Hardening follows the unit's job rather than a universal
`systemd-analyze security` score. Scores are useful review signals, but a backup
unit, network daemon and hardware wake helper legitimately need different
access. `checks.systemd-hardening-invariants` enforces the directives selected
below and rejects privilege growth, root-wide writes, infinite starts and
restart loops through named negative fixtures.

## Constrained helpers

| Units | Required access | Enforced profile |
| --- | --- | --- |
| `tailscale-auth` | Read one agenix credential; contact tailscaled/network | Read-only system, private temporary directory, no privilege growth, network-client families, two-minute timeout |
| `ntfy-failure@` | Read ntfy credentials; make one HTTPS request | Network-client profile, 30-second timeout, no restart, three attempts per minute; no `OnFailure` on itself |
| `free-space-check` | Read Btrfs usage and credentials; write Prometheus textfile; optional HTTPS | Network-client profile with only the textfile directory writable |
| `restic-backup-metric-bootstrap` | Write the initial Prometheus textfile | Offline profile with only the textfile directory writable |
| `lan-inventory-exporter` | Read leases, neighbor data and vendor database; write metrics | Offline profile with only the textfile directory writable |
| `grafana-alert-setup` | Read systemd credentials; call loopback Grafana | Network-client profile, no persistent writes, bounded start |
| `soyo-{boot,activation,health}-trace` | Read system/runtime state; send OTLP to loopback Tempo | Network-client profile, no persistent writes, one-minute timeout |

All profiles also protect the host filesystem, home directories, kernel
settings, modules, logs, control groups, namespaces and process personality,
and deny new privileges, setuid transitions and writable-executable memory.

## Deliberate exceptions

- **Blocky and dnsmasq are the two critical roles.** Their native NixOS units
  and packet-level VM tests remain authoritative. Availability takes priority
  over applying a shared helper profile without daemon-specific evidence.
- **Restic, btrbk, Nix-store optimisation, Btrfs scrub and initrd rollback**
  require broad storage access. They retain explicit resource/priority limits
  and focused backup/impermanence tests instead of a misleading read-only
  profile.
- **Grafana, Prometheus, Loki, Tempo, Alloy and exporters** are upstream
  services with distinct state and socket needs. Repository checks enforce
  guest resource limits; upstream modules own their daemon sandboxing.
- **`disable-thunderbolt-wake`** must write `/proc/acpi/wakeup`; applying kernel
  tunable protection would defeat its sole purpose.
- **tailscaled** configures network interfaces and routes and therefore cannot
  use the unprivileged auth-helper profile.

Any new repository-owned helper must document its reads, writes, address
families, capabilities, timeout and restart behavior here before joining the
reviewed invariant inventory.
