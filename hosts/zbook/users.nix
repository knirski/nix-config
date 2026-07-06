{ config, ... }:
{
  users.users.root.hashedPasswordFile = config.age.secrets.root-password.path;

  users.users.krzysiek = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "docker"
      "libvirtd"
    ];
    hashedPasswordFile = config.age.secrets.krzysiek-password.path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };

  # Virtualisation (for gaming/development VMs)
  virtualisation.libvirtd.enable = true;
  virtualisation.docker.enable = true;

  programs.dconf.enable = true;
}
