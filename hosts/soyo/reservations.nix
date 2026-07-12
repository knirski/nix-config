# hosts/soyo/reservations.nix
#
# Single source of truth for static LAN hosts (DHCP reservation + DNS).
# Imported by:
#   - hosts/soyo/dhcp.nix -> dnsmasq `dhcp-host` reservations; dnsmasq also
#     owns the reverse/PTR records derived from these
#   - hosts/soyo/dns.nix  -> Blocky forward A records
# Editing one entry here keeps the lease, forward DNS, and reverse DNS in sync.
#
# MAC and IP are LAN identifiers, not secrets -> committed in plaintext (no agenix).
# Each name resolves as <name>.home.arpa, plus the bare <name> via the DHCP
# search domain on clients that support it. (The old `.local` names are dropped:
# mDNS/Avahi is out of scope; the appliance serves unicast DNS.)
#
# Each entry: { name = "<hostname>"; mac = "aa:bb:cc:dd:ee:ff"; ip = "10.0.0.x"; }
# A multihomed host (several interfaces active at once) gets one entry per
# interface — same name, different IP — and then resolves to all its IPs (multi-A).
#
# Docs:
#   - dnsmasq dhcp-host: https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
#   - NixOS dnsmasq:     https://search.nixos.org/options?query=services.dnsmasq
let
  networkPolicy = import ./network-policy.nix;
  reservations = [
    # Orbi mesh satellites
    {
      name = "orbi-satellite-1";
      mac = "38:94:ed:25:17:b8";
      ip = "10.0.0.2";
    }
    {
      name = "orbi-satellite-2";
      mac = "38:94:ed:25:16:46";
      ip = "10.0.0.3";
    }

    # Soyo itself. It uses a static IP (set in networking), not DHCP; this entry
    # drives its A/PTR records.
    {
      name = "soyo";
      mac = "00:e0:4c:73:83:5a";
      ip = "10.0.0.9";
    }

    # Other devices
    {
      name = "twins";
      mac = "00:00:c0:1d:5f:9d";
      ip = "10.0.0.10";
    }
    {
      name = "drukarka";
      mac = "38:b1:db:39:fd:f6";
      ip = "10.0.0.11";
    }

    # HP ZBook Studio 16 G10 (desktop/gaming workstation)
    {
      name = "zbook";
      mac = "00:e0:4c:1d:4c:b8";
      ip = "10.0.0.14";
    }

    # czworaczki is multihomed: two ethernet interfaces, both active on the LAN
    # at once, each with its own reservation. The name resolves to both IPs
    # (multi-A); each IP has its own PTR back to `czworaczki`.
    {
      name = "czworaczki";
      mac = "90:09:d0:36:bb:a9";
      ip = "10.0.0.12";
    }
    {
      name = "czworaczki";
      mac = "90:09:d0:36:bb:aa";
      ip = "10.0.0.13";
    }
  ];
in
import ../../lib/network/validate-reservations.nix {
  inherit reservations;
  inherit (networkPolicy) subnetPrefix dynamicPool;
}
