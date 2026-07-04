# LAN Observability Design

Date: 2026-07-04
Status: Approved for spec review

## Goal

Extend Soyo observability for the main `10.0.0.0/24` LAN so Grafana can answer two operational questions quickly:

1. Is the important network gear reachable?
2. Who is currently visible on the LAN, and which devices are unknown?

This design adds declarative probe targets, local blackbox probing, and a lightweight LAN inventory feed. It stays scoped to the current LAN only. It does not attempt guest-network inventory, router replacement, VLAN segmentation, or full network scanning.

## Scope

In scope:

- Add `blackbox_exporter` on Soyo, loopback-only.
- Add Prometheus probe jobs for named infrastructure devices.
- Add a declarative host data file for non-DHCP infrastructure devices we care about.
- Add a periodic inventory collector that emits Prometheus textfile metrics.
- Add a Grafana LAN-oriented dashboard at the root level.
- Update validation documentation.

Initial probe targets:

- Orbi router at `10.0.0.1`
- Orange Funbox 6 at `192.168.1.1`
- Orbi satellites (`RBS50`) once declared in host data
- `printer`
- `czworaczki`

Out of scope:

- Guest network discovery or policy
- DMZ, VLAN, or firewall segmentation work
- SNMP exporter setup
- Router-specific scraping beyond simple HTTP probing
- Active port scanning or deep fingerprinting

## Design Constraints

- Keep DNS and DHCP sacred. Any new observability services remain guest services with explicit resource isolation.
- Keep host-specific device data under `hosts/soyo/`, not embedded in Prometheus expressions.
- Keep reusable mechanics in `modules/nixos/observability.nix`.
- Prefer passive-ish LAN discovery from reservations, leases, and neighbor state over noisy active scanning.
- Preserve the current dashboard split:
  - `Fleet Overview` remains the Grafana home dashboard.
  - `Soyo` remains the folder for appliance-specific dashboards.
  - New LAN summary/dashboard content stays at the root level.

## Architecture

The change is split into three bounded pieces.

### 1. Blackbox Probing

Soyo runs `blackbox_exporter` on loopback only. Prometheus scrapes it locally and defines probe jobs for infrastructure targets declared in host data.

Probe policy:

- ICMP for all declared infrastructure devices.
- HTTP for devices where a web UI exists and a plain GET is meaningful, such as Orbi and Funbox.

Prometheus labels must preserve readable target identity, for example:

- `target_name`
- `target_kind`
- `instance`
- optional site label such as `site="lan"`

### 2. Host-Local Infrastructure Inventory Data

Add `hosts/soyo/network-devices.nix` as the single source of truth for non-DHCP infrastructure targets that should be monitored even if they never appear in `dnsmasq` leases.

Each entry is plain declarative data with fields such as:

- `name`
- `ip`
- `kind` (`router`, `satellite`, `printer`, `host`)
- optional `mac`
- optional `probeHttpUrl`

This file complements `hosts/soyo/reservations.nix`. Reservations remain the source of truth for DHCP/static-name pairs; `network-devices.nix` covers infrastructure that should always be probed.

### 3. LAN Inventory Collector

Add a periodic collector service on Soyo. It reads:

- `hosts/soyo/reservations.nix`
- `hosts/soyo/network-devices.nix`
- `dnsmasq` lease state
- kernel neighbor/ARP state
- MAC OUI vendor mapping data

It emits Prometheus textfile metrics into the existing node exporter textfile directory.

No active network scan is performed in this first version.

## Data Model

### Host Data File

`hosts/soyo/network-devices.nix` should define entries similar to:

```nix
[
  {
    name = "orbi";
    ip = "10.0.0.1";
    kind = "router";
    probeHttpUrl = "http://10.0.0.1/";
  }
]
```

The real file will include the approved initial targets.

### Inventory Metrics

Emit at least two metric families: presence and metadata.

Proposed shapes:

```text
lan_device_seen{ip=...,mac=...,name=...,source=...,vendor=...} 1
lan_device_reserved{ip=...,mac=...,name=...} 1
lan_device_lease_expires_seconds{ip=...,name=...} ...
```

Label behavior:

- `source` distinguishes how the device was seen: `reservation`, `lease`, `neighbor`, or a combined value if multiple sources agree.
- `vendor` comes from MAC OUI when MAC is known; otherwise `unknown`.
- Unknown devices still appear if they are visible in lease or neighbor data.
- Reserved devices still appear even when absent, so the dashboard can distinguish “known but offline” from “unknown but present”.

## Grafana Behavior

Add one new root-level dashboard focused on LAN operations.

Purpose:

- show infrastructure reachability
- show current LAN visibility
- surface unknown devices quickly

Proposed panels:

- infrastructure probe status for Orbi, Funbox, satellites, printer, and `czworaczki`
- probe latency trend
- known devices table
- unknown devices table
- reservations currently absent from the LAN

This dashboard is a summary/router dashboard, not a deep protocol dashboard. It should not absorb detailed DNS/DHCP service analysis from `Soyo Control Plane`.

`Fleet Overview` should remain mostly unchanged. At most, a later follow-up may add a count or a link to the LAN dashboard.

## Failure Modes and Degraded Behavior

- If OUI lookup data is unavailable, inventory still works with `vendor="unknown"`.
- If neighbor state is sparse, reservations and leases still provide partial visibility.
- If HTTP probing redirects or rejects unauthenticated access, ICMP remains the baseline reachability signal.
- Devices absent from reservations, leases, and neighbor state are not discoverable in this version.
- The resulting inventory is useful and practical, but not a claim of complete network discovery.

## Module and File Changes

Expected changes if implemented:

- Create `hosts/soyo/network-devices.nix`
- Update host wiring so Soyo observability can consume those targets
- Extend `modules/nixos/observability.nix` with:
  - blackbox exporter service
  - Prometheus blackbox scrape jobs
  - inventory collector service and timer
  - root-level LAN dashboard provisioning
- Update `docs/validation-checklist.md`
- Optionally extend learning docs if the implementation introduces a new reusable pattern worth documenting

## Validation

Validation after implementation should include:

- Grafana reachable and dashboards provisioned
- root-level LAN dashboard present
- `Node Exporter Full` still present at root
- `Soyo` folder still contains only `Soyo Control Plane`, `Blocky`, and `Dnsmasq`
- blackbox probe targets visible in Prometheus/Grafana
- LAN inventory metrics present in the node exporter textfile scrape
- unknown and known device tables render sensibly from real LAN data

## Future Follow-Ups

Deliberately deferred:

- SNMP trials for Orbi or Funbox if device support proves workable
- guest network visibility if Orbi guest clients are reachable from Soyo
- stronger device classification beyond OUI vendor lookup
- network segmentation for IoT via guest isolation or future VLAN-capable gatewaying
