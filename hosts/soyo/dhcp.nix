let
  reservations = import ./reservations.nix;
  networkPolicy = import ./network-policy.nix;
in
{
  lanAppliance.services.dhcp = {
    enable = true;
    interface = "enp1s0";
    routerAddress = "10.0.0.1";
    dnsServer = "10.0.0.9";
    searchDomain = "home.arpa";
    leaseFile = "/var/lib/dnsmasq/dnsmasq.leases";
    inherit reservations;
    dhcpRanges = [
      "${networkPolicy.subnetPrefix}${toString networkPolicy.dynamicPool.first},${networkPolicy.subnetPrefix}${toString networkPolicy.dynamicPool.last},${networkPolicy.dynamicPool.leaseTime}"
    ];
  };
}
