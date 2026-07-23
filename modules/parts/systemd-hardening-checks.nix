# Enforce reviewed directives, not a generic systemd-analyze score. The latter
# is useful during review but cannot know a unit's required devices or writes.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      services = inputs.self.nixosConfigurations.soyo.config.systemd.services;
      reviewed = {
        tailscale-auth = {
          network = true;
          writes = [ ];
          timeout = "2m";
        };
        "ntfy-failure@" = {
          network = true;
          writes = [ ];
          timeout = "30s";
        };
        free-space-check = {
          network = true;
          writes = [ "/var/lib/prometheus/textfiles" ];
          timeout = "1m";
        };
        restic-backup-metric-bootstrap = {
          network = false;
          writes = [ "/var/lib/prometheus/textfiles" ];
          timeout = "30s";
        };
        lan-inventory-exporter = {
          network = false;
          netlink = true;
          writes = [ "/var/lib/prometheus/textfiles" ];
          timeout = "1m";
        };
        grafana-alert-setup = {
          network = true;
          writes = [ ];
          timeout = "2m";
        };
        soyo-boot-trace = {
          network = true;
          writes = [ ];
          timeout = "1m";
        };
        soyo-activation-trace = {
          network = true;
          writes = [ ];
          timeout = "1m";
        };
        soyo-health-trace = {
          network = true;
          writes = [ ];
          timeout = "1m";
        };
      };
      expectedFamilies =
        {
          network,
          netlink ? false,
        }:
        (
          if network then
            [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ]
          else
            [ "AF_UNIX" ]
        )
        ++ lib.optional netlink "AF_NETLINK";
      commonValid =
        policy: serviceConfig:
        (serviceConfig.NoNewPrivileges or false)
        && (serviceConfig.PrivateTmp or false)
        && (serviceConfig.ProtectSystem or null) == "strict"
        && (serviceConfig.ProtectHome or null) == true
        && (serviceConfig.ProtectKernelTunables or false)
        && (serviceConfig.ProtectKernelModules or false)
        && (serviceConfig.ProtectControlGroups or false)
        && (serviceConfig.RestrictNamespaces or false)
        && (serviceConfig.RestrictSUIDSGID or false)
        && (serviceConfig.LockPersonality or false)
        && (serviceConfig.MemoryDenyWriteExecute or false)
        && (serviceConfig.Restart or null) == "no"
        && (serviceConfig.TimeoutStartSec or null) == policy.timeout
        &&
          (serviceConfig.RestrictAddressFamilies or [ ]) == expectedFamilies {
            inherit (policy) network;
            netlink = policy.netlink or false;
          }
        && (serviceConfig.ReadWritePaths or [ ]) == policy.writes;
      failures = lib.mapAttrsToList (
        name: policy:
        let
          exists = builtins.hasAttr name services;
        in
        lib.optional (
          !exists || !(commonValid policy (if exists then services.${name}.serviceConfig else { }))
        ) name
      ) reviewed;
      flattenedFailures = lib.flatten failures;
      safeFixture = {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        Restart = "no";
        TimeoutStartSec = "30s";
        RestrictAddressFamilies = [ "AF_UNIX" ];
        ReadWritePaths = [ ];
      };
      mutations = import ../../tests/systemd-hardening/mutations.nix;
      mutationAccepted = map (mutation: mutation.name) (
        lib.filter (
          mutation:
          commonValid {
            network = false;
            netlink = false;
            writes = [ ];
            timeout = "30s";
          } (mutation.mutate safeFixture)
        ) mutations
      );
      notification = services."ntfy-failure@";

      # tailscale-auth must be ordered after the real NixOS-generated daemon
      # unit (tailscaled.service), not the misspelled "tailscale.service"
      # that never exists. This checks the contract against a
      # { after, wants, tailscaledExists } shape so the same predicate can be
      # exercised both against the real evaluated Soyo config and against
      # negative fixtures below — string matching alone previously let the
      # bug through because it just repeated the wrong string back at itself.
      tailscaleDependencyValid =
        deps:
        lib.elem "tailscaled.service" deps.after
        && lib.elem "agenix-activation.service" deps.after
        && lib.elem "tailscaled.service" deps.wants
        && deps.tailscaledExists;
      safeTailscaleDeps = {
        after = [
          "tailscaled.service"
          "agenix-activation.service"
        ];
        wants = [ "tailscaled.service" ];
        # Proves tailscaled is an evaluated systemd service, not just an
        # assumed name — services.tailscale.enable must actually have
        # produced this unit in the real Soyo configuration.
        tailscaledExists = builtins.hasAttr "tailscaled" services;
      };
      tailscaleDependencyMutations = import ../../tests/systemd-hardening/tailscale-dependency-mutations.nix;
      tailscaleMutationAccepted = map (mutation: mutation.name) (
        lib.filter (
          mutation: tailscaleDependencyValid (mutation.mutate safeTailscaleDeps)
        ) tailscaleDependencyMutations
      );
      dependenciesValid =
        tailscaleDependencyValid {
          after = services.tailscale-auth.after;
          wants = services.tailscale-auth.wants;
          tailscaledExists = builtins.hasAttr "tailscaled" services;
        }
        && lib.elem "grafana.service" services.grafana-alert-setup.after
        && !(notification.unitConfig ? OnFailure)
        && notification.unitConfig.StartLimitBurst == 3;
    in
    {
      checks.systemd-hardening-invariants =
        assert lib.assertMsg (
          flattenedFailures == [ ]
        ) "reviewed helper hardening drifted: ${lib.concatStringsSep ", " flattenedFailures}";
        assert lib.assertMsg (
          mutationAccepted == [ ]
        ) "hardening validator accepted negative fixtures: ${lib.concatStringsSep ", " mutationAccepted}";
        assert lib.assertMsg (tailscaleMutationAccepted == [ ])
          "tailscale-auth dependency contract accepted negative fixtures: ${lib.concatStringsSep ", " tailscaleMutationAccepted}";
        assert lib.assertMsg dependenciesValid
          "helper dependencies or notification failure-loop guard drifted";
        pkgs.runCommand "systemd-hardening-invariants" { } ''
          touch "$out"
        '';
    };
}
