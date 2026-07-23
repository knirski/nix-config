# Enforces that every operational/critical systemd unit whose silent failure
# matters is wired to the shared ntfy-failure@ notification template, and
# that the template itself can never recurse through OnFailure. Also proves
# (without a real network call) that the smartd and ntfy-failure@ generated
# scripts carry a title, the failing identity, and a non-secret message.
#
# See docs/security/service-hardening.md ("Failure notification classes")
# and docs/testing.md (Named checks) for the design this enforces, and
# docs/superpowers/specs/soyo-dns-dhcp-appliance.md ("Failure Notifications")
# for why this is a reviewed allowlist rather than a global systemd drop-in:
# a blanket OnFailure= on every unit would also fire for irrelevant
# transient units and risks recursing through ntfy-failure@ itself.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      soyoConfig = inputs.self.nixosConfigurations.soyo.config;
      services = soyoConfig.systemd.services;
      hostName = soyoConfig.networking.hostName;

      # Every unit whose silent failure matters for recovery visibility
      # (task O1's enumeration): Btrfs scrub, Nix GC, free-space check,
      # restic, btrbk, the Grafana alert-provisioning helper, and the weekly
      # Nix store optimisation unit. Note: `services.nix-optimise` (the
      # built-in nixpkgs unit for `nix.optimise`) is deliberately disabled in
      # modules/nixos/base.nix and is NOT this unit — the repo's own
      # `nix-store-optimise` unit (also defined in base.nix) is a separate,
      # active, unconditional weekly job that genuinely runs
      # `nix store optimise`, so it belongs in this reviewed list.
      reviewed = [
        "free-space-check"
        "nix-gc"
        "btrbk-${hostName}"
        "grafana-alert-setup"
        "btrfs-scrub"
        "restic-backups-${hostName}"
        "nix-store-optimise"
      ];

      expectedOnFailure = "ntfy-failure@%N.service";
      onFailureValid = unitConfig: (unitConfig.OnFailure or null) == expectedOnFailure;

      missingEdge = lib.filter (
        name: !(builtins.hasAttr name services) || !(onFailureValid services.${name}.unitConfig)
      ) reviewed;

      safeOnFailureFixture = {
        OnFailure = expectedOnFailure;
      };
      onFailureMutations = import ../../tests/failure-notifications/onfailure-mutations.nix;
      onFailureMutationAccepted = map (m: m.name) (
        lib.filter (m: onFailureValid (m.mutate safeOnFailureFixture)) onFailureMutations
      );

      # ntfy-failure@ itself must never carry OnFailure — otherwise its own
      # failure (e.g. curl erroring) could re-trigger itself.
      recursionGuardValid = unitConfig: !(unitConfig ? OnFailure);
      safeRecursionFixture = { };
      recursionMutations = import ../../tests/failure-notifications/notifier-recursion-mutations.nix;
      recursionMutationAccepted = map (m: m.name) (
        lib.filter (m: recursionGuardValid (m.mutate safeRecursionFixture)) recursionMutations
      );
      notifierRecursionSafe = recursionGuardValid services."ntfy-failure@".unitConfig;

      # Real generated artifacts, not fixtures: prove the actual built
      # scripts carry a title, the failing identity, and a non-secret
      # message, and read credentials from a file at runtime rather than
      # inlining them. This is the "stub the network boundary" test — it
      # never invokes curl or contacts a real ntfy endpoint, only inspects
      # the generated command text, the same approach
      # observability-contract-checks.nix uses for the Btrfs metric names.
      # ExecStart is "<script path> %i" — %i is a systemd specifier expanded
      # at runtime, not part of the script path, so take only the first
      # whitespace-separated token.
      unitFailureScript = lib.head (lib.splitString " " services."ntfy-failure@".serviceConfig.ExecStart);
      smartdNotifyScript =
        let
          devices = soyoConfig.services.smartd.devices;
          tokens = lib.splitString " " (lib.head devices).options;
        in
        lib.last tokens;
    in
    {
      checks.failure-notification-invariants =
        assert lib.assertMsg (missingEdge == [ ])
          "reviewed unit(s) missing OnFailure=${expectedOnFailure}: ${lib.concatStringsSep ", " missingEdge}";
        assert lib.assertMsg (onFailureMutationAccepted == [ ])
          "OnFailure validator accepted negative fixtures: ${lib.concatStringsSep ", " onFailureMutationAccepted}";
        assert lib.assertMsg (recursionMutationAccepted == [ ])
          "notifier recursion guard accepted negative fixtures: ${lib.concatStringsSep ", " recursionMutationAccepted}";
        assert lib.assertMsg notifierRecursionSafe
          "ntfy-failure@ itself has an OnFailure set — it could recurse on its own failure";
        pkgs.runCommand "failure-notification-invariants"
          {
            inherit unitFailureScript smartdNotifyScript;
          }
          ''
            # ntfy-failure@: title carries "unit failed", body carries the
            # runtime unit identity placeholder ($SERVICE, expanded by
            # systemd from %i at runtime) and a recovery hint.
            if ! grep -qF 'Title: ${hostName} unit failed' "$unitFailureScript"; then
              echo "ntfy-failure@ script missing expected title" >&2
              exit 1
            fi
            if ! grep -qF '$SERVICE failed on ${hostName}' "$unitFailureScript"; then
              echo "ntfy-failure@ script missing failing-unit identity in message" >&2
              exit 1
            fi
            if ! grep -qF 'journalctl -u $SERVICE' "$unitFailureScript"; then
              echo "ntfy-failure@ script missing recovery hint" >&2
              exit 1
            fi

            # smartd notify: title carries "SMART warning", body carries
            # device/failtype/message identity, and credentials are read
            # from a file at runtime rather than inlined into the script.
            if ! grep -qF 'Title: ${hostName} SMART warning' "$smartdNotifyScript"; then
              echo "smartd notify script missing expected title" >&2
              exit 1
            fi
            if ! grep -qF '$DEVICE' "$smartdNotifyScript" || ! grep -qF '$FAILTYPE' "$smartdNotifyScript"; then
              echo "smartd notify script missing device/failtype identity in message" >&2
              exit 1
            fi
            if ! grep -qF '$MESSAGE' "$smartdNotifyScript"; then
              echo "smartd notify script missing smartd's own message text" >&2
              exit 1
            fi
            if ! grep -qE 'TOKEN=\$\(cat ' "$smartdNotifyScript" || ! grep -qE 'TOPIC=\$\(cat ' "$smartdNotifyScript"; then
              echo "smartd notify script does not read credentials from a file at runtime" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
