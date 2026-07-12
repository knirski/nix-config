# Shared Tailscale mesh VPN aspect.
#
# Extracted from server.nix and workstation.nix — both had the same
# Tailscale auth oneshot pattern with slightly different args.
# Toggle this in the host assembler and configure via host data.
{
  aspects.nixos.tailscale =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.lanAppliance.services.tailscale;
      hardening = import ../../lib/systemd-hardening.nix;
    in
    {
      options.lanAppliance.services.tailscale = {
        enable = lib.mkEnableOption "Tailscale mesh VPN with automatic auth-key connection";

        authKeyFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to a Tailscale auth key file (agenix secret). If set, authenticates automatically on first boot.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "--advertise-routes=10.0.0.0/24" ];
          description = "Extra CLI arguments passed to 'tailscale up', e.g. --advertise-routes=...";
        };

        nice = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Nice level for the auth oneshot service (10 = lower priority than default).";
        };

        isolateResources = lib.mkEnableOption "resource limits for Tailscale on a role-constrained host";
      };

      config = lib.mkIf cfg.enable {
        services.tailscale.enable = true;

        # Tailscale is remote-administration infrastructure, not one of Soyo's
        # two critical LAN roles. Keep it useful during an incident without
        # allowing it to crowd out DNS or DHCP.
        systemd.services.tailscaled.serviceConfig = lib.mkIf cfg.isolateResources {
          MemoryMax = "256M";
          CPUQuota = "25%";
          Nice = 5;
        };

        # Oneshot: authenticate Tailscale once the agenix secret is decrypted.
        # Only runs on first boot (when Tailscale hasn't authenticated yet).
        systemd.services.tailscale-auth = lib.mkIf (cfg.authKeyFile != null) {
          description = "Authenticate Tailscale with auth key";
          after = [
            "tailscale.service"
            "agenix-activation.service"
          ];
          wants = [ "tailscale.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig =
            hardening.networkClient
            // {
              Type = "oneshot";
              ExecStart = lib.getExe (
                pkgs.writeShellApplication {
                  name = "tailscale-auth";
                  runtimeInputs = [
                    pkgs.coreutils
                    pkgs.gnugrep
                    pkgs.tailscale
                  ];
                  text = ''
                    if ! tailscale status 2>/dev/null | grep -qE '^\d+\.\d+\.\d+\.\d+\s'; then
                      tailscale up --auth-key "$(cat ${cfg.authKeyFile})" ${builtins.concatStringsSep " " cfg.extraArgs}
                    fi
                  '';
                }
              );
              MemoryMax = "32M";
              CPUQuota = "10%";
              TimeoutStartSec = "2m";
              Restart = "no";
            }
            // lib.optionalAttrs (cfg.nice != 0) {
              Nice = cfg.nice;
            };
        };
      };
    };
}
