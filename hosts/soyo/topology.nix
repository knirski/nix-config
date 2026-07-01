# hosts/soyo/topology.nix
#
# Soyo-specific topology definitions for nix-topology.
# Physical connections, running services, and network assignments
# that nix-topology cannot auto-extract.
#
# Everything else (interfaces, IPs, firewall rules) is auto-extracted
# from the NixOS configuration by the nix-topology NixOS module.
{
  topology.self = {
    interfaces.enp1s0.physicalConnections = [
      # Connected to the Orbi router's LAN port
      {
        node = "router";
        interface = "lan";
      }
    ];
  };
}
