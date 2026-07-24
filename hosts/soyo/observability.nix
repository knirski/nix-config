let
  networkData = import ./network.nix;
in
{
  lanAppliance.services.observability = {
    enable = true;
    inherit networkData;
    lanInterface = "enp1s0";
    # dnsmasq listens on 5353 (Blocky owns :53).
    dnsmasqExporter.dnsmasqListenAddress = "127.0.0.1:5353";
    grafana = {
      enable = true;
      # Bind on all interfaces — reachable both from localhost and the LAN
      # (openFirewall below opens port 3000 on lanInterface for the latter).
      listenAddress = "0.0.0.0";
    };
    openFirewall = true;
  };
}
