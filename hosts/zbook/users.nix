{ config, pkgs, ... }:
{
  users.users.root.hashedPasswordFile = config.age.secrets.root-password.path;

  users.users.krzysiek = {
    isNormalUser = true;
    shell = pkgs.zsh;
    ignoreShellProgramCheck = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
      "video"
      "libvirtd"
    ];
    hashedPasswordFile = config.age.secrets.krzysiek-password.path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
    ];
  };

  # Virtualisation (for gaming/development VMs)
  virtualisation.libvirtd.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.dconf.enable = true;
}
