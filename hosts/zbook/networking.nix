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
    firewall = {
      enable = true;

      # LocalSend uses the same port for its HTTP transfer endpoint and UDP
      # discovery announcements. Keep the exception limited to zbook's
      # physical LAN interfaces; tailscale0 is already trusted separately.
      interfaces = {
        enp0s13f0u3 = {
          allowedTCPPorts = [ 53317 ];
          allowedUDPPorts = [ 53317 ];
        };
        wlp0s20f3 = {
          allowedTCPPorts = [ 53317 ];
          allowedUDPPorts = [ 53317 ];
        };
      };
    };

    # Prepend local LAN search domain ahead of Tailscale MagicDNS so
    # unqualified lookups like 'soyo' resolve to the LAN IP first.
    resolvconf.extraConfig = ''
      search_domains="home.arpa"
    '';
  };

  lanAppliance.services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
  };
}
