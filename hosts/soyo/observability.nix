{
  lanAppliance.services.observability = {
    enable = true;
    nodeExporter.listenAddress = "10.0.0.9:9100";
    dnsmasqExporter.listenAddress = "10.0.0.9:9153";
    # dnsmasq listens on 5353 (Blocky owns :53), interface-bound to enp1s0 (not loopback).
    dnsmasqExporter.dnsmasqListenAddress = "10.0.0.9:5353";
    dnsmasqExporter.leasesPath = "/var/lib/dnsmasq/dnsmasq.leases";
    openFirewall = true;
  };
}
