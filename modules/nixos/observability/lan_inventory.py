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
