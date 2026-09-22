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
      "i2c"
    ];
    hashedPasswordFile = config.age.secrets.krzysiek-password.path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../secrets/krzysiek-authorized-key.pub)
      (builtins.readFile ../../secrets/zbook-authorized-key.pub)
    ];
  };

  # libvirtd comes from the workstation aspect (modules/nixos/workstation.nix);
  # it was disabled temporarily while diagnosing the NVMe/PCIe suspend issue,
  # but that made no difference to the hangs.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.dconf.enable = true;
}
