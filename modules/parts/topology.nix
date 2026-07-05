# flake-parts module: expose nix-topology infrastructure diagram output.
#
# LAN devices are derived from hosts/soyo/reservations.nix — the single source
# of truth. Add a device there, it appears in the diagram automatically.
# Soyo itself is auto-extracted by the NixOS module (interfaces, IPs, services).
#
# Render with: nix build .#topology.x86_64-linux && cp result/main.svg .
# Result: result/main.svg (physical topology), result/network.svg (network view)
#
# Docs: https://oddlama.github.io/nix-topology/
{
  inputs,
  self,
  lib,
  ...
}:
let
  inherit (inputs) nix-topology;

  networkData = import ../../hosts/soyo/network.nix;
  inherit (networkData) reservations;

  # Group reservations by name (multihomed hosts have multiple entries)
  grouped = lib.foldl (
    acc: r:
    acc
    // {
      ${r.name} = (acc.${r.name} or [ ]) ++ [
        {
          inherit (r) name mac ip;
          isWiFi = lib.hasPrefix "orbi-satellite" r.name;
          isNAS = r.name == "czworaczki";
        }
      ];
    }
  ) { } reservations;

  # Build one topology node per device group
  deviceNodes = lib.mapAttrsToList (
    name: entries:
    let
      first = builtins.head entries;
      # One interface per entry (multihomed = multiple interfaces)
      interfaces = lib.listToAttrs (
        lib.imap0 (i: e: {
          name = if builtins.length entries == 1 then "lan" else "eth${toString i}";
          value = {
            network = "lan";
            inherit (e) mac;
          }
          // lib.optionalAttrs e.isWiFi { type = "wifi"; };
        }) entries
      );

      attrs = {
        inherit interfaces;
      }
      // lib.optionalAttrs first.isNAS {
        name = "Synology DS423+ (${name})";
        deviceType = "nas";
      }
      // lib.optionalAttrs first.isWiFi {
        name = "Orbi Satellite ${lib.last (lib.splitString "-" name)}";
        deviceType = "switch";
      }
      // lib.optionalAttrs (!first.isNAS && !first.isWiFi) (
        if name == "twins" then
          {
            name = "Backup NAS (${name})";
            deviceType = "nas";
          }
        else if name == "drukarka" then
          {
            name = "Drukarka (Printer)";
            deviceType = "server";
          }
        else
          {
            inherit name;
            deviceType = "server";
          }
      );
    in
    lib.nameValuePair name attrs
  ) grouped;

  # Generate all nodes: upstreams + router + LAN devices (excluding soyo)
  allNodes = [
    {
      name = "dns4eu";
      value = {
        name = "DNS4EU NoAds (DoH)";
        deviceType = "server";
        interfaces.public = {
          network = "internet";
        };
      };
    }
    {
      name = "quad9";
      value = {
        name = "Quad9 DNS (DoH)";
        deviceType = "server";
        interfaces.public = {
          network = "internet";
        };
      };
    }
    {
      name = "router";
      value = {
        name = "Orbi Router (10.0.0.1)";
        deviceType = "router";
        interfaces = {
          wan = {
            network = "internet";
          };
          lan = {
            network = "lan";
            addresses = [ "10.0.0.1/24" ];
            physicalConnections = [
              {
                node = "soyo";
                interface = "enp1s0";
              }
              {
                node = "czworaczki";
                interface = "eth0";
              }
              {
                node = "orbi-satellite-1";
                interface = "lan";
              }
              {
                node = "orbi-satellite-2";
                interface = "lan";
              }
              {
                node = "twins";
                interface = "lan";
              }
              {
                node = "drukarka";
                interface = "lan";
              }
            ];
          };
        };
      };
    }
  ]
  ++ lib.filter (nv: nv.name != "soyo") deviceNodes;
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.topology =
        (import nix-topology {
          pkgs = pkgs.extend (import "${nix-topology}/pkgs/default.nix");
          modules = [
            {
              nixosConfigurations = lib.filterAttrs (_: c: c.config ? topology) self.nixosConfigurations;
            }
            {
              networks = {
                lan = {
                  name = "Home LAN";
                  cidrv4 = "10.0.0.0/24";
                };
                rescue = {
                  name = "Direct-Link Rescue";
                  cidrv4 = "192.168.254.0/30";
                };
                internet = {
                  name = "Internet";
                  cidrv4 = "0.0.0.0/0";
                };
              };

              nodes = builtins.listToAttrs allNodes;
            }
          ];
        }).config.output;
    };
}
