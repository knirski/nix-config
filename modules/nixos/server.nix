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

      # earlyoom: proactive OOM killer. If a service (e.g. Grafana, Loki) leaks
      # memory, the kernel OOM can freeze the box. earlyoom kills the culprit
      # while the system is still responsive, protecting critical services.
      services.earlyoom = {
        enable = true;
        freeMemThreshold = 10; # kill when <10% memory free
        freeSwapThreshold = 10; # kill when <10% swap free
        extraArgs = [
          "--prefer '(^|/)blocky$|(^|/)dnsmasq$|(^|/)sshd?$" # protect critical services
          "--ignore '(^|/)systemd|(^|/)X|(^|/)pipewire" # never kill core services
        ];
      };
    };
}
