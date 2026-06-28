let
  reservations = import ./reservations.nix;
in
{
  lanAppliance.services.dhcp = {
    enable = true;
    interface = "enp1s0";
    routerAddress = "10.0.0.1";
    dnsServer = "10.0.0.9";
    searchDomain = "home.arpa";
    leaseFile = "/var/lib/dnsmasq/dnsmasq.leases";
    reservations = reservations;
    dhcpRanges = [ "10.0.0.50,10.0.0.199,12h" ];
  };
}
