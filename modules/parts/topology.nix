# flake-parts module: expose nix-topology infrastructure diagram output.
#
# Generates SVG network topology diagrams from NixOS configurations.
# Render with: nix build .#topology.x86_64-linux.config.output
# Result: result/ (contains main.svg, network.svg)
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
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages.topology =
        (import nix-topology {
          pkgs = pkgs.extend (import "${nix-topology}/pkgs/default.nix");
          modules = [
            # Auto-extract topology from all NixOS configs that have `topology` set
            {
              nixosConfigurations = lib.filterAttrs (_: c: c.config ? topology) self.nixosConfigurations;
            }
            # Global topology: external devices, networks, connections
            {
              nodes.router = {
                name = "Orbi RBK53 Router";
                deviceType = "router";
                interfaces = {
                  wan = {
                    network = "internet";
                  };
                  lan = {
                    network = "lan";
                    mac = "00:00:00:00:00:01";
                  };
                };
              };
              nodes.nas = {
                name = "Synology DS423+";
                deviceType = "nas";
                interfaces.lan = {
                  network = "lan";
                };
              };
              nodes.dns4eu = {
                name = "DNS4EU NoAds";
                deviceType = "server";
                interfaces.public = {
                  network = "internet";
                };
              };
              nodes.quad9 = {
                name = "Quad9 DNS";
                deviceType = "server";
                interfaces.public = {
                  network = "internet";
                };
              };
              networks.lan = {
                name = "Home LAN";
                cidrv4 = "10.0.0.0/24";
              };
              networks.rescue = {
                name = "Direct-Link Rescue";
                cidrv4 = "192.168.254.0/30";
              };
              networks.internet = {
                name = "Internet";
                cidrv4 = "0.0.0.0/0";
              };
              nodes.router.interfaces.wan.physicalConnections = [ ];
            }
          ];
        }).config.output;
    };
}
