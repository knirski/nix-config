{
  flake.modules.nixos.server =
    { lib, ... }:
    {
      networking.useNetworkd = true;
      systemd.network.enable = true;

      # systemd-networkd-wait-online is notorious for blocking activation on
      # single-interface hosts. We know the interface is up — no need to wait.
      systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

      services.openssh.enable = true;
      services.openssh.settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
}
