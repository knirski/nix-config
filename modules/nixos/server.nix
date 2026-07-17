# Server role aspect: systemd-networkd, earlyoom OOM killer.
#
# OpenSSH and Tailscale were extracted to shared ssh.nix and tailscale.nix
# aspects — toggle those separately in the host assembler.
{
  aspects.nixos.server =
    { lib, ... }:
    {
      config = {
        # Health checks consume this declarative marker instead of inferring the
        # host role from mutable network state.
        environment.etc."nix-config/role".text = "appliance\n";

        networking.useNetworkd = true;

        systemd = {
          network.enable = true;

          # systemd-networkd-wait-online is notorious for blocking activation on
          # single-interface hosts. We know the interface is up — no need to wait.
          services.systemd-networkd-wait-online.enable = lib.mkForce false;
        };

        # Blacklist i915 on headless servers. No display is attached, so loading
        # the GPU driver is pointless and triggers harmless but noisy kernel
        # WARN_ON backtraces (adlp_tc_phy_connect on Alder Lake N).
        boot.blacklistedKernelModules = [ "i915" ];

        services = {
          # earlyoom: proactive OOM killer. If a service (e.g. Grafana, Loki) leaks
          # memory, the kernel OOM can freeze the box. earlyoom kills the culprit
          # while the system is still responsive, protecting critical services.
          #
          # Note: earlyoom 1.9.x uses -p/--prefer with a regex pattern. The NixOS
          # module passes extraArgs as a flat list; verify with:
          #   systemctl cat earlyoom | grep EARLYOOM_ARGS
          earlyoom = {
            enable = true;
            freeMemThreshold = 10;
            freeSwapThreshold = 10;
          };
        };
      };
    };
}
