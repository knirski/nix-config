{ config, ... }:
{
  # Desktop uses NetworkManager for network management
  networking.networkmanager.enable = true;

  networking.firewall.enable = true;

  workstation.services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.tailscale-auth-key.path;
  };
}
