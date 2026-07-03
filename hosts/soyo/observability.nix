{
  lanAppliance.services.observability = {
    enable = true;
    # dnsmasq listens on 5353 (Blocky owns :53).
    dnsmasqExporter.dnsmasqListenAddress = "127.0.0.1:5353";
    grafana.enable = true;
    openFirewall = true;
  };
}
