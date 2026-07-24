{ config, ... }:
{
  # Desktop uses NetworkManager for network management
  networking = {
    networkmanager.enable = true;
    dhcpcd.enable = false;
    firewall.enable = true;
  };

  lanAppliance.services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
  };
}
