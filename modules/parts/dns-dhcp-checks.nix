# Pure evaluation tests for Soyo's two critical network roles. Keep these
# assertions at the structured NixOS-option layer: rendered service files are
# implementation details, while these values describe the intended contract.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      soyo = inputs.self.nixosConfigurations.soyo.config;
      reservations = import ../../hosts/soyo/reservations.nix;
      networkPolicy = import ../../hosts/soyo/network-policy.nix;

      blocky = soyo.services.blocky;
      blockySource = soyo.lanAppliance.services.blocky;
      blockySettings = blocky.settings;
      dhcp = soyo.lanAppliance.services.dhcp;
      dnsmasq = soyo.services.dnsmasq;
      dnsmasqSettings = dnsmasq.settings;
      firewall = soyo.networking.firewall;
      lanFirewall = firewall.interfaces.${blockySource.lanInterface};
      persistence = soyo.preservation.preserveAt."/persist";

      setEqual = left: right: lib.sort builtins.lessThan left == lib.sort builtins.lessThan right;
      normalizedMappings = lib.mapAttrs (
        _: value: lib.sort builtins.lessThan (lib.splitString "," value)
      );

      names = lib.unique (map (reservation: reservation.name) reservations);
      ipsFor =
        name:
        lib.concatStringsSep "," (
          map (reservation: reservation.ip) (lib.filter (reservation: reservation.name == name) reservations)
        );
      expectedForwardRecords = lib.listToAttrs (
        lib.concatMap (name: [
          (lib.nameValuePair name (ipsFor name))
          (lib.nameValuePair "${name}.home.arpa" (ipsFor name))
        ]) names
      );
      expectedDhcpHosts = map (
        reservation: "${reservation.mac},${reservation.ip},${reservation.name},infinite"
      ) reservations;
      expectedDhcpOptions = [
        "option:router,10.0.0.1"
        "option:dns-server,10.0.0.9"
        "option:domain-search,home.arpa"
      ];

      dnsListeners = blockySettings.ports.dns;
      reverseTarget = blockySettings.conditional.mapping."0.0.10.in-addr.arpa" or null;
      expectedDhcpRange = "${networkPolicy.subnetPrefix}${toString networkPolicy.dynamicPool.first},${networkPolicy.subnetPrefix}${toString networkPolicy.dynamicPool.last},${networkPolicy.dynamicPool.leaseTime}";
      persistedDirectories = map (entry: entry.directory) persistence.directories;
      dnsExposedInterfaces = builtins.attrNames (
        lib.filterAttrs (
          _: rules: lib.elem 53 (rules.allowedTCPPorts or [ ]) || lib.elem 53 (rules.allowedUDPPorts or [ ])
        ) firewall.interfaces
      );

      testResults = {
        critical-services-enabled = blocky.enable && dnsmasq.enable && dhcp.enable;

        # The same validated inventory must drive both services. Comparing the
        # complete generated sets also catches missing, extra, and stale records.
        reservation-source = dhcp.reservations == reservations;
        forward-a-records =
          normalizedMappings blockySettings.customDNS.mapping == normalizedMappings expectedForwardRecords;
        dhcp-host-mappings = setEqual dnsmasqSettings."dhcp-host" expectedDhcpHosts;

        # Blocky owns client-facing DNS on :53. dnsmasq owns lease-aware PTR
        # answers on a distinct port, and Blocky delegates the LAN reverse zone.
        reverse-zone-forwarding = reverseTarget == "10.0.0.9:5353";
        blocky-lan-listeners =
          blockySource.lanInterface == "enp1s0"
          && setEqual dnsListeners [
            "127.0.0.1:53"
            "${dhcp.dnsServer}:53"
          ];
        compatible-dns-bindings =
          dnsmasqSettings.port == [ 5353 ]
          && dnsmasqSettings.interface == [ dhcp.interface ]
          && dnsmasqSettings."bind-interfaces" == [ true ]
          && lib.all (listener: !(lib.hasSuffix ":5353" listener)) dnsListeners;
        dns-firewall-exposure =
          setEqual dnsExposedInterfaces [ blockySource.lanInterface ]
          && lib.elem 53 lanFirewall.allowedTCPPorts
          && lib.elem 53 lanFirewall.allowedUDPPorts
          && !(lib.elem 53 firewall.allowedTCPPorts)
          && !(lib.elem 53 firewall.allowedUDPPorts);
        dhcp-firewall-exposure = lib.elem 67 lanFirewall.allowedUDPPorts;

        # DHCP tells clients that the router remains their gateway, while Soyo
        # is their sole DNS server and home.arpa is their search domain.
        dhcp-network-policy =
          dhcp.routerAddress == "10.0.0.1"
          && dhcp.dnsServer == "10.0.0.9"
          && dhcp.searchDomain == "home.arpa"
          && setEqual dnsmasqSettings."dhcp-option" expectedDhcpOptions
          && dhcp.dhcpRanges == [ expectedDhcpRange ]
          && dnsmasqSettings."dhcp-range" == [ expectedDhcpRange ];
        local-domain-policy =
          dnsmasqSettings.domain == [ "home.arpa" ]
          && dnsmasqSettings.local == [ "/home.arpa/" ]
          && dnsmasqSettings."dhcp-fqdn" == [ true ]
          && dnsmasqSettings."expand-hosts" == [ true ];
        dnsmasq-safety-policy =
          !dnsmasq.resolveLocalQueries
          && dnsmasqSettings."dhcp-authoritative" == [ true ]
          && dnsmasqSettings."domain-needed" == [ true ]
          && dnsmasqSettings."bogus-priv" == [ true ]
          && dnsmasqSettings."local-service" == [ true ];
        persistent-lease-database =
          lib.hasPrefix "/var/lib/dnsmasq/" dhcp.leaseFile
          && dnsmasqSettings."dhcp-leasefile" == [ dhcp.leaseFile ]
          && lib.elem "/var/lib/dnsmasq" persistedDirectories;
      };

      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      # This proves declarative wiring, not packet-level reachability. Whether
      # Blocky can actually reach dnsmasq for delegated PTR queries belongs in
      # the phase-2 VM test and the live-host health check.
      checks.dns-dhcp-config =
        assert
          failed == [ ]
          || throw "Soyo DNS/DHCP configuration tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "dns-dhcp-config-test" { } ''
          touch $out
        '';
    };
}
