{
  flake.modules.nixos.server = {
    networking.useNetworkd = true;
    systemd.network.enable = true;

    services.openssh.enable = true;
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };
}
