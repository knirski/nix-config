{
  aspects.nixos.dhcp =
    { lib, config, ... }:
    let
      cfg = config.lanAppliance.services.dhcp;
      leaseDir = dirOf cfg.leaseFile;
      reservationLines = map (r: "${r.mac},${r.ip},${r.name},infinite") cfg.reservations;
    in
    {
      options.lanAppliance.services.dhcp = {
        enable = lib.mkEnableOption "dnsmasq DHCP";
        interface = lib.mkOption { type = lib.types.str; };
        routerAddress = lib.mkOption { type = lib.types.str; };
        dnsServer = lib.mkOption { type = lib.types.str; };
        searchDomain = lib.mkOption { type = lib.types.str; };
        leaseFile = lib.mkOption { type = lib.types.str; };
        dhcpRanges = lib.mkOption { type = lib.types.listOf lib.types.str; };
        reservations = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                mac = lib.mkOption { type = lib.types.str; };
                ip = lib.mkOption { type = lib.types.str; };
              };
            }
          );
        };
      };

      config = lib.mkIf cfg.enable {
        services.dnsmasq = {
          enable = true;
          resolveLocalQueries = false;
          settings = {
            port = 5353; # Blocky owns :53; dnsmasq serves local reverse on 5353.
            inherit (cfg) interface;
            "bind-interfaces" = true;
            "dhcp-authoritative" = true;
            "dhcp-range" = cfg.dhcpRanges;
            "dhcp-host" = reservationLines;
            "dhcp-option" = [
              "option:router,${cfg.routerAddress}"
              "option:dns-server,${cfg.dnsServer}"
              "option:domain-search,${cfg.searchDomain}"
            ];
            "dhcp-fqdn" = true;
            "dhcp-leasefile" = cfg.leaseFile;
            domain = cfg.searchDomain;
            local = "/${cfg.searchDomain}/";
            "expand-hosts" = true;
            "domain-needed" = true;
            "bogus-priv" = true;
            "local-service" = true;
          };
        };

        # Pinned nixpkgs generates `mkdir -m 755 -p /var/lib/dnsmasq` in its
        # preStart, which trips ShellCheck SC2174 because -m with -p only
        # controls the deepest directory. The directory is separately owned by
        # the explicit tmpfiles rule below. Keep strict checks enabled globally
        # and scope this upstream-owned exception to dnsmasq only.
        systemd.services.dnsmasq.enableStrictShellChecks = false;

        # Lease DB lives on /persist so leases survive reboots/rebuilds.
        systemd.tmpfiles.rules = [
          "d ${leaseDir} 0750 dnsmasq dnsmasq -"
        ];

        networking.firewall.interfaces.${cfg.interface}.allowedUDPPorts = [ 67 ];
      };
    };
}
