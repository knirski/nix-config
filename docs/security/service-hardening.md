# Service hardening policy

**Lifecycle: active.** This records the reviewed privilege, write and network
requirements for repository-owned systemd units. It complements resource
limits; neither mechanism proves immunity to every resource-exhaustion event.

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
