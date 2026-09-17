{
  config,
  lib,
  pkgs,
  ...
}:
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

  # Keep the virt-manager client available, but stop libvirtd while diagnosing
  # the NVMe/PCIe suspend issue. mkForce overrides the workstation aspect's
  # default so the daemon cannot be restarted by the shared role module.
  virtualisation.libvirtd.enable = lib.mkForce false;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  programs.dconf.enable = true;
}
