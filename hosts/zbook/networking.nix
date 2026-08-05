{ config, pkgs, ... }:
{
  # Desktop uses NetworkManager for network management
  networking = {
    networkmanager = {
      enable = true;
      # NixOS no longer bundles VPN plugins by default.  Keep OpenVPN as a
      # NetworkManager connection so the desktop shell can control it too.
      plugins = [ pkgs.networkmanager-openvpn ];
    };
    dhcpcd.enable = false;
    firewall.enable = true;
  };

  lanAppliance.services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
  };
}
