{
  lanAppliance.services.observability = {
    enable = true;
    # dnsmasq listens on 5353 (Blocky owns :53), interface-bound to enp1s0 (not loopback).
    dnsmasqExporter.dnsmasqListenAddress = "10.0.0.9:5353";
    openFirewall = true;
  };
}
