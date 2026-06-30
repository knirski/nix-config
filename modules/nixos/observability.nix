{
  flake.modules.nixos.observability =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.observability;
    in
    {
      options.lanAppliance.services.observability = {
        enable = lib.mkEnableOption "prometheus node_exporter and dnsmasq exporter (scraping/dashboards stay off-box)";
        nodeExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9:9100";
            description = "Listen address for the prometheus node_exporter (LAN interface, not 0.0.0.0).";
          };
        };
        dnsmasqExporter = {
          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9:9153";
          };
          dnsmasqListenAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.0.0.9:53";
            description = "dnsmasq address for lease stats; must match where dnsmasq is reachable from Soyo.";
          };
          leasesPath = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/dnsmasq/dnsmasq.leases";
          };
        };
        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the LAN firewall for exporter ports (9100 and 9153). Enable only when a scraper is configured off-box.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.prometheus.exporters.node = {
          enable = true;
          listenAddress = cfg.nodeExporter.listenAddress;
        };

        services.prometheus.exporters.dnsmasq = {
          enable = true;
          listenAddress = cfg.dnsmasqExporter.listenAddress;
          dnsmasqListenAddress = cfg.dnsmasqExporter.dnsmasqListenAddress;
          leasesPath = cfg.dnsmasqExporter.leasesPath;
        };

        # Resource isolation: exporters are guest services; prevent them from
        # starving Blocky or dnsmasq under memory/CPU pressure.
        systemd.services.prometheus-node-exporter.serviceConfig = {
          MemoryMax = "64M";
          CPUQuota = "10%";
        };

        systemd.services.prometheus-dnsmasq-exporter.serviceConfig = {
          MemoryMax = "64M";
          CPUQuota = "10%";
        };

        networking.firewall = lib.mkIf cfg.openFirewall {
          interfaces.enp1s0.allowedTCPPorts = [
            9100
            9153
          ];
        };
      };
    };
}
