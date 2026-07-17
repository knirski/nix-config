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
            network = policy.network;
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
      dependenciesValid =
        lib.elem "tailscale.service" services.tailscale-auth.after
        && lib.elem "agenix-activation.service" services.tailscale-auth.after
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
        assert lib.assertMsg dependenciesValid
          "helper dependencies or notification failure-loop guard drifted";
        pkgs.runCommand "systemd-hardening-invariants" { } ''
          touch "$out"
        '';
    };
}
