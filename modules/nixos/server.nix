{
  aspects.nixos.server =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.tailscale;
    in
    {
      options.lanAppliance.services.tailscale = {
        enable = lib.mkEnableOption "Tailscale mesh VPN for secure off-LAN admin";
        authKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to a Tailscale auth key file (agenix secret). If set, Tailscale authenticates automatically on start. If null, run 'sudo tailscale up' manually after deploy.";
        };
        isSubnetRouter = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Advertise Soyo as a subnet router so remote machines can reach the whole 10.0.0.0/24 LAN through it.";
        };
      };

      config = {
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
        #
        # Note: earlyoom 1.9.x uses -p/--prefer with a regex pattern. The NixOS
        # module passes extraArgs as a flat list; verify with:
        #   systemctl cat earlyoom | grep EARLYOOM_ARGS
        services.earlyoom = {
          enable = true;
          freeMemThreshold = 10;
          freeSwapThreshold = 10;
        };

        # Tailscale: secure mesh VPN for remote admin. No open ports, no DynDNS.
        # Authentication is either automatic (authKeyFile) or manual (tailscale up).
        services.tailscale = lib.mkIf cfg.enable {
          enable = true;
          # Don't use the NixOS module's auth key option — it conflicts with
          # the agenix activation ordering. Instead, a oneshot service handles
          # the first authentication after the secret is available.
        };

        # Oneshot: authenticate Tailscale once the agenix secret is decrypted.
        # Only runs on first boot (when Tailscale hasn't authenticated yet).
        systemd.services.tailscale-auth = lib.mkIf (cfg.enable && cfg.authKeyFile != null) {
          description = "Authenticate Tailscale with auth key";
          after = [
            "tailscale.service"
            "agenix-activation.service"
          ];
          wants = [ "tailscale.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "tailscale-auth" ''
              if tailscale status 2>/dev/null | grep -q stopped; then
                AUTH_KEY=$(cat ${cfg.authKeyFile})
                EXTRA=""
                ${if cfg.isSubnetRouter then ''EXTRA="--advertise-routes=10.0.0.0/24"'' else ""}
                tailscale up --auth-key "$AUTH_KEY" $EXTRA
              fi
            '';
            MemoryMax = "32M";
            CPUQuota = "10%";
            Nice = 10;
          };
        };
      };
    };
}
