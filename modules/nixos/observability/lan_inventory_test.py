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
            {"ip": "10.0.0.11", "mac": "38:b1:db:39:fd:f6", "state": ["REACHABLE"]},
            {"ip": "10.0.0.77", "mac": "b8:27:eb:12:34:56", "state": ["STALE"]},
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
