# LAN Observability Implementation Plan

**Lifecycle: completed.** Preserved as implementation history; consult the
corresponding design and current modules for present behavior.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add passive LAN inventory and blackbox reachability monitoring for Soyo's main LAN, with a new root-level Grafana dashboard that surfaces important infrastructure and unknown devices quickly.

**Architecture:** Keep `hosts/soyo/reservations.nix` as the DNS/DHCP source of truth, then add `hosts/soyo/network.nix` as a host-local namespace that layers observability metadata and extra infrastructure targets on top. Extend `modules/nixos/observability.nix` to synthesize blackbox targets, run a periodic textfile collector, and provision the new dashboard without disturbing the existing Grafana split.

**Tech Stack:** NixOS modules, Prometheus, node_exporter textfile collector, blackbox_exporter, Grafana JSON provisioning, Python 3, `iproute2`, `arp-scan` vendor database

---

## File Structure

- `hosts/soyo/reservations.nix`
  Keeps the existing DHCP/DNS reservation list unchanged. This remains the critical appliance source of truth required by the repo invariants.

- `hosts/soyo/network.nix`
  New host-local network namespace. Wraps `reservations` and adds observability-only `monitoredInfrastructure` and `deviceMeta`.

- `hosts/soyo/observability.nix`
  Passes `networkData` into the observability aspect.

- `modules/parts/topology.nix`
  Switch to consuming `network.nix.reservations` so non-critical LAN consumers read the host-local namespace.

- `modules/nixos/observability.nix`
  Extend the existing aspect with blackbox exporter configuration, target synthesis, LAN inventory service/timer, and the new root-level dashboard.

- `modules/nixos/observability/lan_inventory.py`
  New helper script for passive LAN inventory collection and Prometheus textfile rendering.

- `modules/nixos/observability/lan_inventory_test.py`
  New `unittest` coverage for the collector's merge logic and metric rendering.

- `docs/validation-checklist.md`
  Add runtime validation steps for blackbox probes, LAN inventory metrics, and the new dashboard.

- `docs/learning/design-journey.md`
  Add the learning note for the host-local network namespace and why observability data is adjacent to, but not merged into, the DHCP/DNS source of truth.

### Task 1: Introduce the host-local network namespace

**Files:**

- Create: `hosts/soyo/network.nix`
- Modify: `hosts/soyo/observability.nix`
- Modify: `modules/parts/topology.nix`

- [ ] **Step 1: Prove the namespace file does not exist yet**

Run:

```bash
nix eval --json --expr '(import ./hosts/soyo/network.nix).monitoredInfrastructure'
```

Expected: FAIL with a path-not-found error for `./hosts/soyo/network.nix`.

- [ ] **Step 2: Create `hosts/soyo/network.nix` with reservations, monitor-only infrastructure, and observability metadata**

```nix
# hosts/soyo/network.nix
#
# Host-local network namespace.
# - reservations stay the DNS/DHCP source of truth
# - monitoredInfrastructure covers non-DHCP or off-LAN devices we still want probed
# - deviceMeta adds observability-only labels without polluting the reservation schema
{
  reservations = import ./reservations.nix;

  monitoredInfrastructure = [
    {
      name = "orbi";
      ip = "10.0.0.1";
      kind = "router";
      displayName = "Orbi Router";
      probeHttpUrl = "http://10.0.0.1/";
    }
    {
      name = "funbox";
      ip = "192.168.1.1";
      kind = "router";
      displayName = "Orange Funbox 6";
      probeHttpUrl = "http://192.168.1.1/";
    }
  ];

  deviceMeta = {
    "orbi-satellite-1" = {
      kind = "satellite";
      displayName = "Orbi Satellite 1";
      monitor = true;
    };
    "orbi-satellite-2" = {
      kind = "satellite";
      displayName = "Orbi Satellite 2";
      monitor = true;
    };
    drukarka = {
      kind = "printer";
      displayName = "Printer";
      monitor = true;
    };
    czworaczki = {
      kind = "host";
      displayName = "Czworaczki";
      monitor = true;
    };
  };
}
```

- [ ] **Step 3: Pass `networkData` into the observability host policy**

`hosts/soyo/observability.nix` already exists with the basic observability config. Add the `networkData` import and pass-through:

```diff
--- a/hosts/soyo/observability.nix
+++ b/hosts/soyo/observability.nix
@@ -1,5 +1,9 @@
+let
+  networkData = import ./network.nix;
+in
 {
   lanAppliance.services.observability = {
     enable = true;
+    networkData = networkData;
     # dnsmasq listens on 5353 (Blocky owns :53).
     dnsmasqExporter.dnsmasqListenAddress = "127.0.0.1:5353";
     grafana.enable = true;
```

- [ ] **Step 4: Rewire topology to read reservations through the new namespace**

`modules/parts/topology.nix` already exists with reservations imported directly. Change just the import line — all downstream topology logic (`grouped`, `deviceNodes`, `isWiFi`/`isNAS` heuristics, upstream nodes) stays untouched:

```diff
--- a/modules/parts/topology.nix
+++ b/modules/parts/topology.nix
@@ -17,7 +17,8 @@
 let
   inherit (inputs) nix-topology;

-  reservations = import ../../hosts/soyo/reservations.nix;
+  networkData = import ../../hosts/soyo/network.nix;
+  reservations = networkData.reservations;

   # Group reservations by name (multihomed hosts have multiple entries)
   grouped = lib.foldl (
```

- [ ] **Step 5: Run the namespace checks and verify topology didn't regress**

Run:

```bash
nix eval --json --expr '(import ./hosts/soyo/network.nix).deviceMeta' | jq 'keys'
nix build .#topology.x86_64-linux
```

Expected:

- first command prints the monitored device keys, including `"czworaczki"` and `"drukarka"`
- second command succeeds (verified visually by inspecting `result/main.svg` for the expected device nodes)

- [ ] **Step 6: Commit the namespace introduction**

```bash
git add hosts/soyo/network.nix hosts/soyo/observability.nix modules/parts/topology.nix
git commit -m "feat(observability): add soyo network data namespace"
```

### Task 2: Add blackbox exporter provisioning and target synthesis

**Files:**

- Modify: `modules/nixos/observability.nix`

- [ ] **Step 1: Verify blackbox jobs are absent before the change**

Run:

```bash
nix eval --json .#nixosConfigurations.soyo.config.services.prometheus.scrapeConfigs \
  | jq 'map(.job_name) | map(select(startswith("blackbox")))'
```

Expected: `[]`. This check protects the existing `node`, `dnsmasq`, and `blocky` scrapes from accidental replacement in the next step.

- [ ] **Step 2: Add `networkData` and `blackboxExporter` options**

The module already declares `nodeExporter`, `dnsmasqExporter`, `grafana`, and `openFirewall` options. Add only the new ones:

```nix
# modules/nixos/observability.nix — add inside the existing
# options.lanAppliance.services.observability = { ... } block
networkData = lib.mkOption {
  type = lib.types.submodule {
    options = {
      reservations = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            mac = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
          };
        });
        default = [ ];
        description = "DHCP/DNS reservation list, same shape as hosts/soyo/reservations.nix.";
      };
      monitoredInfrastructure = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
            kind = lib.mkOption { type = lib.types.str; };
            displayName = lib.mkOption { type = lib.types.str; };
            probeHttpUrl = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
          };
        });
        default = [ ];
        description = "Infrastructure targets that should always be probed (e.g. non-DHCP or off-LAN devices).";
      };
      deviceMeta = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            kind = lib.mkOption { type = lib.types.str; };
            displayName = lib.mkOption { type = lib.types.str; };
            monitor = lib.mkOption { type = lib.types.bool; default = false; };
          };
        });
        default = { };
        description = "Observability-only labels keyed by reservation name — keeps rich labels off the DHCP schema.";
      };
    };
  };
  default = {
    reservations = [ ];
    monitoredInfrastructure = [ ];
    deviceMeta = { };
  };
  description = "Host-local network data used for LAN dashboards, blackbox probes, and passive inventory.";
};

blackboxExporter = {
  listenAddress = lib.mkOption {
    type = lib.types.str;
    default = "127.0.0.1";
    description = "Loopback listen address for blackbox_exporter (module appends :9115).";
  };
};
```

- [ ] **Step 3: Synthesize probe targets from `reservations`, `monitoredInfrastructure`, and `deviceMeta`**

```nix
# modules/nixos/observability.nix
let
  cfg = config.lanAppliance.services.observability;
  grafanaCfg = cfg.grafana;
  networkData = cfg.networkData;
  deviceMeta = networkData.deviceMeta or { };

  reservationProbeTargets = lib.concatMap (
    r:
    let
      meta = deviceMeta.${r.name} or null;
    in
    lib.optionals ((meta != null) && ((meta.monitor or false))) [
      {
        name = r.name;
        ip = r.ip;
        kind = meta.kind or "host";
        displayName = meta.displayName or r.name;
      }
    ]
  ) networkData.reservations;

  probeTargets = reservationProbeTargets ++ (map (
    t:
    t
    // {
      displayName = t.displayName or t.name;
    }
  ) networkData.monitoredInfrastructure);

  httpProbeTargets = lib.filter (t: t ? probeHttpUrl) probeTargets;

  mkStaticLabelTarget = t: target: {
    targets = [ target ];
    labels = {
      target_name = t.name;
      target_kind = t.kind;
      display_name = t.displayName;
      site = "lan";
    };
  };
in
```

- [ ] **Step 4: Enable blackbox exporter and add Prometheus ICMP and HTTP jobs**

**Insertion point:** The blackbox exporter service and its systemd limit go in the **first** `mkMerge` element (always active under `cfg.enable`). The blackbox scrape jobs go in a **new third** `mkMerge` element — the NixOS module system merges `scrapeConfigs` lists across `mkMerge` elements automatically, so this appends to the existing `node`/`dnsmasq`/`blocky` jobs without overwriting them.

```nix
# modules/nixos/observability.nix
# --- first mkMerge element (always-on) — add after existing node_exporter block ---
services.prometheus.exporters.blackbox = {
  enable = true;
  listenAddress = cfg.blackboxExporter.listenAddress;
  configFile = pkgs.writeText "blackbox.yml" (
    builtins.toJSON {
      modules = {
        icmp.prober = "icmp";
        http_2xx = {
          prober = "http";
          timeout = "5s";
          http = {
            preferred_ip_protocol = "ip4";
            method = "GET";
          };
        };
      };
    }
  );
};

systemd.services.prometheus-blackbox-exporter.serviceConfig = {
  MemoryMax = "96M";
  CPUQuota = "10%";
};

# --- third mkMerge element — add as a new list item inside the mkMerge ---
(lib.mkIf grafanaCfg.enable {
  services.prometheus.scrapeConfigs = [
    {
      job_name = "blackbox-exporter";
      static_configs = [ { targets = [ "127.0.0.1:9115" ]; } ];
    }
    {
      job_name = "blackbox-icmp";
      metrics_path = "/probe";
      params.module = [ "icmp" ];
      static_configs = map (t: mkStaticLabelTarget t t.ip) probeTargets;
      relabel_configs = [
        {
          source_labels = [ "__address__" ];
          target_label = "__param_target";
        }
        {
          source_labels = [ "__param_target" ];
          target_label = "instance";
        }
        {
          target_label = "__address__";
          replacement = "127.0.0.1:9115";
        }
      ];
    }
    {
      job_name = "blackbox-http";
      metrics_path = "/probe";
      params.module = [ "http_2xx" ];
      static_configs = map (t: mkStaticLabelTarget t t.probeHttpUrl) httpProbeTargets;
      relabel_configs = [
        {
          source_labels = [ "__address__" ];
          target_label = "__param_target";
        }
        {
          source_labels = [ "__param_target" ];
          target_label = "instance";
        }
        {
          target_label = "__address__";
          replacement = "127.0.0.1:9115";
        }
      ];
    }
  ];
})
```

- [ ] **Step 5: Evaluate the blackbox jobs and labels**

Run:

```bash
nix eval --json .#nixosConfigurations.soyo.config.services.prometheus.scrapeConfigs \
  | jq '[.[] | select(.job_name | startswith("blackbox")) | .job_name]'
```

Expected:

```json
[
  "blackbox-exporter",
  "blackbox-icmp",
  "blackbox-http"
]
```

- [ ] **Step 6: Commit the blackbox wiring**

```bash
git add modules/nixos/observability.nix
git commit -m "feat(observability): add lan blackbox probes"
```

### Task 3: Add the passive LAN inventory collector and tests

**Files:**

- Create: `modules/nixos/observability/lan_inventory.py`
- Create: `modules/nixos/observability/lan_inventory_test.py`
- Modify: `modules/nixos/observability.nix`

- [ ] **Step 1: Add the failing collector test first**

```python
# modules/nixos/observability/lan_inventory_test.py
import unittest

from lan_inventory import collect_inventory, render_metrics


class LanInventoryTests(unittest.TestCase):
    def test_reserved_and_unknown_devices_are_emitted(self):
        network_data = {
            "reservations": [
                {"name": "drukarka", "mac": "38:b1:db:39:fd:f6", "ip": "10.0.0.11"},
                {"name": "czworaczki", "mac": "90:09:d0:36:bb:a9", "ip": "10.0.0.12"},
            ],
            "monitoredInfrastructure": [
                {"name": "orbi", "ip": "10.0.0.1", "kind": "router", "displayName": "Orbi Router"},
            ],
            "deviceMeta": {
                "drukarka": {"kind": "printer", "displayName": "Printer", "monitor": True},
                "czworaczki": {"kind": "host", "displayName": "Czworaczki", "monitor": True},
            },
        }
        leases = [
            {"ip": "10.0.0.11", "mac": "38:b1:db:39:fd:f6", "name": "drukarka", "expires": 1720227600},
        ]
        neigh = [
            {"dst": "10.0.0.11", "lladdr": "38:b1:db:39:fd:f6", "state": ["REACHABLE"]},
            {"dst": "10.0.0.77", "lladdr": "b8:27:eb:12:34:56", "state": ["STALE"]},
        ]
        vendors = {
            "38:B1:DB": "Brother",
            "B8:27:EB": "Raspberry Pi",
        }

        rows = collect_inventory(network_data, leases, neigh, vendors)
        metrics = render_metrics(rows)

        self.assertIn('lan_device_reserved{ip="10.0.0.11",mac="38:b1:db:39:fd:f6",name="drukarka"} 1', metrics)
        self.assertIn('lan_device_reserved{ip="10.0.0.12",mac="90:09:d0:36:bb:a9",name="czworaczki"} 1', metrics)
        self.assertIn('lan_device_seen{ip="10.0.0.77",mac="b8:27:eb:12:34:56",name="unknown-10-0-0-77",source="neighbor",vendor="Raspberry Pi"} 1', metrics)
        self.assertIn('lan_device_seen{ip="10.0.0.11",mac="38:b1:db:39:fd:f6",name="drukarka",source="lease+neighbor+reservation",vendor="Brother"} 1', metrics)
        self.assertNotIn('lan_device_seen{ip="10.0.0.12",mac="90:09:d0:36:bb:a9",name="czworaczki"', metrics)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to confirm it fails before implementation**

Run:

```bash
python3 modules/nixos/observability/lan_inventory_test.py
```

Expected: FAIL with `ModuleNotFoundError: No module named 'lan_inventory'`.

- [ ] **Step 3: Implement the collector as a small tested helper**

```python
# modules/nixos/observability/lan_inventory.py
import argparse
import json
from pathlib import Path


def canonical_prefix(mac: str) -> str:
    parts = mac.upper().split(":")
    return ":".join(parts[:3]) if len(parts) >= 3 else ""


def parse_leases(path: Path):
    rows = []
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        expiry, mac, ip, name, _client_id = line.split()
        rows.append({"ip": ip, "mac": mac.lower(), "name": name, "expires": int(expiry)})
    return rows


def parse_neighbors(raw: str):
    parsed = json.loads(raw)
    rows = []
    for item in parsed:
        if "dst" not in item or "lladdr" not in item:
            continue
        rows.append({
            "ip": item["dst"],
            "mac": item["lladdr"].lower(),
            "state": item.get("state", []),
        })
    return rows


def parse_vendors(path: Path):
    vendors = {}
    for line in path.read_text(errors="ignore").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 1)
        if len(fields) != 2:
            continue
        vendors[fields[0].upper()] = fields[1].strip()
    return vendors


def collect_inventory(network_data, leases, neigh, vendors):
    reservations = network_data.get("reservations", [])
    reserved_rows = [
        {
            "ip": reservation["ip"],
            "mac": reservation["mac"].lower(),
            "name": reservation["name"],
        }
        for reservation in reservations
    ]
    reserved_by_ip = {row["ip"]: dict(row) for row in reserved_rows}
    seen_rows = {}

    for lease in leases:
        row = seen_rows.setdefault(lease["ip"], {
            "ip": lease["ip"],
            "mac": lease["mac"],
            "name": lease["name"],
            "sources": set(),
            "expires": None,
        })
        row["mac"] = row.get("mac") or lease["mac"]
        row["name"] = row.get("name") or lease["name"]
        row["sources"].add("lease")
        row["expires"] = lease["expires"]

    for neighbor in neigh:
        row = seen_rows.setdefault(neighbor["ip"], {
            "ip": neighbor["ip"],
            "mac": neighbor["mac"],
            "name": f'unknown-{neighbor["ip"].replace(".", "-")}',
            "sources": set(),
            "expires": None,
        })
        row["mac"] = row.get("mac") or neighbor["mac"]
        row["sources"].add("neighbor")

    for row in seen_rows.values():
        prefix = canonical_prefix(row.get("mac", ""))
        row["vendor"] = vendors.get(prefix, "unknown")
        if row["ip"] in reserved_by_ip:
            row["sources"].add("reservation")
            row["name"] = reserved_by_ip[row["ip"]]["name"]
            row["mac"] = reserved_by_ip[row["ip"]]["mac"]

    return {
        "reserved": sorted(reserved_rows, key=lambda row: tuple(int(part) for part in row["ip"].split("."))),
        "seen": sorted(seen_rows.values(), key=lambda row: tuple(int(part) for part in row["ip"].split("."))),
    }


def render_metrics(inventory):
    out = []
    out.append("# HELP lan_device_seen Device currently visible in passive LAN data sources")
    out.append("# TYPE lan_device_seen gauge")
    out.append("# HELP lan_device_reserved Device declared in reservations")
    out.append("# TYPE lan_device_reserved gauge")
    out.append("# HELP lan_device_lease_expires_seconds DHCP lease expiry as a Unix timestamp")
    out.append("# TYPE lan_device_lease_expires_seconds gauge")

    for row in inventory["reserved"]:
        labels = f'ip="{row["ip"]}",mac="{row["mac"]}",name="{row["name"]}"'
        out.append(f'lan_device_reserved{{{labels}}} 1')

    for row in inventory["seen"]:
        labels = f'ip="{row["ip"]}",mac="{row["mac"]}",name="{row["name"]}"'
        source = "+".join(sorted(row["sources"]))
        out.append(f'lan_device_seen{{{labels},source="{source}",vendor="{row["vendor"]}"}} 1')
        if row.get("expires") is not None:
            out.append(f'lan_device_lease_expires_seconds{{ip="{row["ip"]}",name="{row["name"]}"}} {row["expires"]}')
    return "\n".join(out) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--network-data", required=True)
    parser.add_argument("--leases", required=True)
    parser.add_argument("--neighbors", required=True)
    parser.add_argument("--vendor-db", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    network_data = json.loads(Path(args.network_data).read_text())
    leases = parse_leases(Path(args.leases))
    neighbors = parse_neighbors(Path(args.neighbors).read_text())
    vendors = parse_vendors(Path(args.vendor_db))
    inventory = collect_inventory(network_data, leases, neighbors, vendors)
    metrics = render_metrics(inventory)
    Path(args.output).write_text(metrics)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Wire the collector into the observability module with a service and timer**

**Insertion point:** Add these to the **first** `mkMerge` element (always active under `cfg.enable`).

```nix
# modules/nixos/observability.nix
let
  lanInventoryNetworkJson = pkgs.writeText "lan-network.json" (builtins.toJSON cfg.networkData);
  lanInventoryScript = pkgs.writeShellApplication {
    name = "lan-inventory-exporter";
    runtimeInputs = [ pkgs.iproute2 pkgs.python3 ];
    text = ''
      set -euo pipefail
      tmpdir="$(mktemp -d)"
      trap 'rm -rf "$tmpdir"' EXIT

      ${pkgs.iproute2}/bin/ip -json neigh show dev enp1s0 > "$tmpdir/neighbors.json"

      exec ${pkgs.python3}/bin/python3 ${./observability/lan_inventory.py} \
        --network-data ${lanInventoryNetworkJson} \
        --leases ${cfg.dnsmasqExporter.leasesPath} \
        --neighbors "$tmpdir/neighbors.json" \
        --vendor-db ${pkgs.arp-scan}/etc/arp-scan/mac-vendor.txt \
        --output /var/lib/prometheus/textfiles/lan_inventory.prom
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus/textfiles 0755 prometheus prometheus -"
  ];

  systemd.services.lan-inventory-exporter = {
    description = "Emit passive LAN inventory metrics for node_exporter textfile collector";
    after = [ "network-online.target" "dnsmasq.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "prometheus";
      Group = "prometheus";
      SupplementaryGroups = [ "dnsmasq" ];
      ExecStart = "${lanInventoryScript}/bin/lan-inventory-exporter";
      MemoryMax = "96M";
      CPUQuota = "10%";
    };
  };

  systemd.timers.lan-inventory-exporter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "30s";
      Unit = "lan-inventory-exporter.service";
    };
  };
}
```

- [ ] **Step 5: Run the collector tests and the Nix evaluation**

Run:

```bash
python3 modules/nixos/observability/lan_inventory_test.py
nix eval --raw .#nixosConfigurations.soyo.config.systemd.services.lan-inventory-exporter.serviceConfig.ExecStart
```

Expected:

- Python test exits `OK`
- Nix eval prints a store path ending in `/bin/lan-inventory-exporter`

- [ ] **Step 6: Commit the collector work**

```bash
git add modules/nixos/observability.nix modules/nixos/observability/lan_inventory.py modules/nixos/observability/lan_inventory_test.py
git commit -m "feat(observability): add passive lan inventory collector"
```

### Task 4: Add the LAN dashboard, docs, deployment, and runtime validation

**Files:**

- Modify: `modules/nixos/observability.nix`
- Modify: `docs/validation-checklist.md`
- Modify: `docs/learning/design-journey.md`

- [ ] **Step 1: Confirm the LAN dashboard is not defined in the module yet**

Run:

```bash
grep -rn "lan-overview\|LAN Overview" modules/nixos/observability.nix
```

Expected: no matches.

- [ ] **Step 2: Add a new root-level `LAN Overview` dashboard next to `Fleet Overview` and `Node Exporter Full`**

```nix
# modules/nixos/observability.nix
let
  lanOverviewJson = pkgs.writeText "lan-overview.json" (
    builtins.toJSON {
      title = "LAN Overview";
      uid = "lan-overview";
      editable = false;
      refresh = "30s";
      time = {
        from = "now-6h";
        to = "now";
      };
      tags = [ "lan" "network" "blackbox" ];
      panels = [
        {
          id = 1;
          type = "table";
          title = "Infrastructure Reachability";
          gridPos = { x = 0; y = 0; w = 12; h = 8; };
          targets = [
            {
              refId = "A";
              datasource = { type = "prometheus"; uid = "soyo-prometheus"; };
              expr = "max by (display_name, target_kind, instance, job) (probe_success{job=~\"blackbox-(icmp|http)\", site=\"lan\"})";
              format = "table";
              instant = true;
            }
          ];
        }
        {
          id = 2;
          type = "timeseries";
          title = "Probe Latency";
          gridPos = { x = 12; y = 0; w = 12; h = 8; };
          targets = [
            {
              refId = "A";
              datasource = { type = "prometheus"; uid = "soyo-prometheus"; };
              expr = "probe_duration_seconds{job=~\"blackbox-(icmp|http)\", site=\"lan\"}";
              legendFormat = "{{display_name}} ({{job}})";
            }
          ];
        }
        {
          id = 3;
          type = "table";
          title = "Known Devices";
          gridPos = { x = 0; y = 8; w = 16; h = 10; };
          targets = [
            {
              refId = "A";
              datasource = { type = "prometheus"; uid = "soyo-prometheus"; };
              expr = "lan_device_seen{name!~\"unknown-.*\"}";
              format = "table";
              instant = true;
            }
          ];
        }
        {
          id = 4;
          type = "table";
          title = "Unknown Devices";
          gridPos = { x = 16; y = 8; w = 8; h = 10; };
          targets = [
            {
              refId = "A";
              datasource = { type = "prometheus"; uid = "soyo-prometheus"; };
              expr = "lan_device_seen{name=~\"unknown-.*\"}";
              format = "table";
              instant = true;
            }
          ];
        }
        {
          id = 5;
          type = "table";
          title = "Reservations Currently Absent";
          gridPos = { x = 0; y = 18; w = 24; h = 8; };
          targets = [
            {
              refId = "A";
              datasource = { type = "prometheus"; uid = "soyo-prometheus"; };
              expr = "lan_device_reserved unless on (ip, name, mac) lan_device_seen";
              format = "table";
              instant = true;
            }
          ];
        }
      ];
    }
  );
in
{
  services.grafana.provision.dashboards.settings = {
    apiVersion = 1;
    providers = [
      {
        name = "fleet";
        type = "file";
        options.path = pkgs.runCommand "fleet-grafana-dashboards" { } ''
          mkdir -p $out
          cp ${fleetJson} $out/001-fleet-overview.json
          cp ${nodeExporterJson} $out/002-node-exporter-full.json
          cp ${lanOverviewJson} $out/003-lan-overview.json
        '';
      }
      {
        name = "soyo";
        type = "file";
        folder = "Soyo";
        folderUid = "soyo";
        options.path = pkgs.runCommand "soyo-grafana-dashboards" { } ''
          mkdir -p $out
          cp ${homeJson} $out/001-soyo-control-plane.json
          cp ${dnsmasqJson} $out/dnsmasq.json
          cp ${blockyJson} $out/blocky.json
        '';
      }
    ];
  };
}
```

This keeps `LAN Overview`, `Fleet Overview`, and `Node Exporter Full` at the root while leaving the `Soyo` folder provider untouched.

- [ ] **Step 3: Update validation and learning docs**

```md
# docs/validation-checklist.md
- [ ] **blackbox probe targets visible**
  Command: `curl -s http://soyo:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test("blackbox")) | {job: .labels.job, instance: .labels.instance, target_name: .labels.target_name, health: .health}'`
  Expected: healthy `blackbox-icmp` targets for Orbi, Funbox, satellites, `drukarka`, and `czworaczki`; healthy `blackbox-http` targets for Orbi and Funbox.

- [ ] **LAN inventory metrics present**
  Command: `curl -s http://soyo:9100/metrics | grep '^lan_device_'`
  Expected: metrics present, including reserved devices and at least one visible device row.

- [ ] **LAN dashboard provisioned at root**
  Command: `curl -s -u admin:"$(sudo cat /run/agenix/grafana-admin-password)" http://soyo:3000/api/search | jq '[.[] | {title, uid, folderTitle}] | map(select(.title == "LAN Overview" or .title == "Fleet Overview" or .title == "Node Exporter Full"))'` <!-- gitleaks:allow; password is read from agenix at runtime -->
  Expected: `LAN Overview`, `Fleet Overview`, and `Node Exporter Full` appear at the root; the `Soyo` folder still contains only `Soyo Control Plane`, `Blocky`, and `Dnsmasq`.
```

```md
# docs/learning/design-journey.md
## Host-local network namespaces

`hosts/soyo/reservations.nix` stays the appliance truth for DHCP and forward/reverse DNS because those roles are critical. Observability needs more shape than `{ name; mac; ip; }`, though, so the repo adds `hosts/soyo/network.nix` as an adjacent namespace instead of mutating the reservation schema. That keeps the critical path boring while still giving Grafana and Prometheus richer labels, extra off-LAN targets, and future room for inventory metadata.
```

- [ ] **Step 4: Run full validation, deploy to Soyo, and check the live system**

Run:

```bash
nix flake check
sudo nixos-rebuild switch --flake .#soyo --target-host krzysiek@soyo --use-remote-sudo
curl -s http://soyo:9100/metrics | grep '^lan_device_'
curl -s http://soyo:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test("blackbox")) | {job: .labels.job, instance: .labels.instance, target_name: .labels.target_name, health: .health}'
curl -s -u admin:"$(sudo cat /run/agenix/grafana-admin-password)" http://soyo:3000/api/search | jq '[.[] | {title, uid, folderTitle}]' # gitleaks:allow; runtime agenix secret
```

Expected:

- `nix flake check` passes
- deployment completes successfully
- textfile metrics are present under node_exporter
- blackbox targets are healthy for the approved devices
- `LAN Overview`, `Fleet Overview`, and `Node Exporter Full` are at the root
- the `Soyo` folder still contains only `Soyo Control Plane`, `Blocky`, and `Dnsmasq`

- [ ] **Step 5: Commit the dashboard and docs**

```bash
git add modules/nixos/observability.nix docs/validation-checklist.md docs/learning/design-journey.md
git commit -m "feat(observability): add lan overview dashboard"
```
