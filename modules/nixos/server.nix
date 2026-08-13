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

          # Headless appliance: a failed boot must not drop into an emergency
          # shell on a console nobody can reach. Prefer continuing to boot — the
          # boot-generations fallback (see hosts/soyo/boot.nix) is the recovery
          # path. (srvos server profile)
          enableEmergencyMode = false;

          # Servers never sleep: suspend would take DNS/DHCP offline until
          # someone physically wakes the box. (srvos server profile)
          sleep.settings.Sleep = {
            AllowSuspend = "no";
            AllowHibernation = "no";
          };

          # Hardware watchdog: force a reboot if the kernel wedges. Soyo hung
          # completely on 2026-08-11 (ksoftirqd stuck in the rpfilter match —
          # see AGENTS.md "Recurrent wedge + VPD access failure") and needed a
          # manual cold restart; a watchdog would have recovered it in ~15 s.
          # Requires a hardware watchdog device (/dev/watchdog); the N150's
          # iTCO_wdt module is loaded in hosts/soyo/boot.nix. Verify after
          # deploy with `wdctl`. (srvos server profile)
          settings.Manager = {
            RuntimeWatchdogSec = "15s";
            RebootWatchdogSec = "30s";
          };

          # Remote builds (nixos-rebuild --target-host) run on this box. Make
          # the nix daemon's builds the kernel OOM killer's first victims so
          # blocky/dnsmasq survive memory pressure — the same isolation
          # philosophy as the guest-service limits (invariant 2).
          # (srvos nixos/common/nix.nix)
          services.nix-daemon.serviceConfig.OOMScoreAdjust = 250;
        };

        # Run remote nix-daemon builds at batch CPU / idle IO priority so they
        # never starve DNS/DHCP, mirroring the guest-service isolation in
        # invariant 2. (srvos nixos/common/nix.nix)
        nix = {
          daemonCPUSchedPolicy = "batch";
          daemonIOSchedClass = "idle";
          daemonIOSchedPriority = 7;
        };

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
