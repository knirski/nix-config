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
