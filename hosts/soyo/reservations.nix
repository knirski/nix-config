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
#
# Docs:
#   - dnsmasq dhcp-host: https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
#   - NixOS dnsmasq:     https://search.nixos.org/options?query=services.dnsmasq
[
  # Orbi mesh satellites
  { name = "orbi-satellite-1"; mac = "38:94:ed:25:17:b8"; ip = "10.0.0.2"; }
  { name = "orbi-satellite-2"; mac = "38:94:ed:25:16:46"; ip = "10.0.0.3"; }

  # Soyo itself. It uses a static IP (set in networking), not DHCP; this entry
  # mirrors the previous config and drives its A/PTR records.
  { name = "soyo"; mac = "00:e0:4c:73:83:5a"; ip = "10.0.0.9"; }

  # Other devices
  { name = "twins"; mac = "00:00:c0:1d:5f:9d"; ip = "10.0.0.10"; }
  { name = "drukarka"; mac = "38:b1:db:39:fd:f6"; ip = "10.0.0.11"; }

  # czworaczki has two interfaces with separate reservations. The previous
  # Blocky config resolved the name `czworaczki` to .12 only. dns.nix must
  # decide forward-A handling for the duplicate name (e.g. A -> .12 only, or
  # both as round-robin); PTR for each IP is unambiguous.
  { name = "czworaczki"; mac = "90:09:d0:36:bb:a9"; ip = "10.0.0.12"; }
  { name = "czworaczki"; mac = "90:09:d0:36:bb:aa"; ip = "10.0.0.13"; }
]
