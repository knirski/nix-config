# Enforces that the Btrfs usage/threshold Prometheus metric names emitted by
# free-space-check (modules/nixos/maintenance.nix) and referenced by the
# soyo_disk_space_low Grafana alert (lib/observability/grafana-alert-setup.nix)
# never drift apart. Both sides import the same lib/observability/btrfs-metrics.nix
# helper; this check proves the generated artifacts actually agree, not just
# that the source files look right.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      btrfsMetrics = import ../../lib/observability/btrfs-metrics.nix;
      services = inputs.self.nixosConfigurations.soyo.config.systemd.services;

      # The real generated artifacts: writeShellApplication outputs whose
      # ExecStart is the path to the built script. Reading their content
      # (rather than trusting the source, which could import the helper and
      # still typo the interpolation) is what proves the contract holds.
      producerScript = services.free-space-check.serviceConfig.ExecStart;
      alertScript = services.grafana-alert-setup.serviceConfig.ExecStart;

      # Exact-token membership, not substring matching: a naive `hasInfix
      # "btrfs_usage_percent" expr` would still "pass" for the actual bug this
      # check exists to catch, because "soyo_btrfs_usage_percent" contains
      # "btrfs_usage_percent" as a substring. Splitting on non-identifier
      # characters and requiring the exact token closes that hole.
      wordTokens = str: lib.filter builtins.isString (builtins.split "[^A-Za-z0-9_]+" str);

      # Pure predicate over plain strings, so the same logic runs against the
      # real generated scripts and against hand-mutated fixtures below.
      btrfsAlertContractValid =
        fixture:
        let
          producerTokens = wordTokens fixture.producerText;
          exprTokens = wordTokens fixture.alertExpr;
        in
        lib.elem btrfsMetrics.usagePercent producerTokens
        && lib.elem btrfsMetrics.thresholdPercent producerTokens
        && lib.elem btrfsMetrics.usagePercent exprTokens
        && lib.elem btrfsMetrics.thresholdPercent exprTokens
        # An explicit host label match on *each* metric occurrence, not just
        # the label substring appearing somewhere in the whole expression —
        # a single `hasInfix "host=\""` check would still accept an
        # expression where only one side of the comparison carries the
        # label (e.g. `btrfs_usage_percent{host="soyo"} >
        # btrfs_usage_threshold_percent`), which is exactly the
        # cross-host-comparison hazard this contract exists to prevent.
        && lib.hasInfix "${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}=\"" fixture.alertExpr
        && lib.hasInfix "${btrfsMetrics.thresholdPercent}{${btrfsMetrics.hostLabel}=\"" fixture.alertExpr;

      safeFixture = {
        producerText = ''
          # TYPE ${btrfsMetrics.usagePercent} gauge
          ${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}="soyo"} 42
          # TYPE ${btrfsMetrics.thresholdPercent} gauge
          ${btrfsMetrics.thresholdPercent}{${btrfsMetrics.hostLabel}="soyo"} 85
        '';
        alertExpr = "${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}=\"soyo\"} > ${btrfsMetrics.thresholdPercent}{${btrfsMetrics.hostLabel}=\"soyo\"}";
      };

      mutations = import ../../tests/observability/btrfs-metric-contract-mutations.nix;
      mutationAccepted = map (mutation: mutation.name) (
        lib.filter (mutation: btrfsAlertContractValid (mutation.mutate safeFixture)) mutations
      );
    in
    {
      checks.btrfs-alert-metric-contract =
        assert lib.assertMsg (mutationAccepted == [ ])
          "btrfs alert metric contract accepted negative fixtures: ${lib.concatStringsSep ", " mutationAccepted}";
        pkgs.runCommand "btrfs-alert-metric-contract"
          {
            inherit producerScript alertScript;
          }
          ''
            # Real generated artifacts, not the fixture above: prove
            # free-space-check's textfile output and grafana-alert-setup's
            # provisioned expression actually agree at build time.
            # \b enforces an exact token match — a plain substring grep would
            # still "pass" for a stray "soyo_" prefix, since it contains the
            # bare name as a substring (that was the actual C2 bug).
            if ! grep -qE '\b${btrfsMetrics.usagePercent}\b' "$producerScript"; then
              echo "producer script missing ${btrfsMetrics.usagePercent}" >&2
              exit 1
            fi
            if ! grep -qE '\b${btrfsMetrics.thresholdPercent}\b' "$producerScript"; then
              echo "producer script missing ${btrfsMetrics.thresholdPercent}" >&2
              exit 1
            fi
            if ! grep -qE '\b${btrfsMetrics.usagePercent}\b' "$alertScript"; then
              echo "alert script missing ${btrfsMetrics.usagePercent}" >&2
              exit 1
            fi
            if ! grep -qE '\b${btrfsMetrics.thresholdPercent}\b' "$alertScript"; then
              echo "alert script missing ${btrfsMetrics.thresholdPercent}" >&2
              exit 1
            fi
            # Each metric occurrence must carry its own explicit host label
            # immediately after it, not merely appear somewhere in the same
            # file — otherwise a one-sided label drop (label on one metric,
            # missing on the other) would slip through undetected.
            if ! grep -qF '${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}="' "$alertScript"; then
              echo "alert script's ${btrfsMetrics.usagePercent} occurrence has no immediate ${btrfsMetrics.hostLabel} label match" >&2
              exit 1
            fi
            if ! grep -qF '${btrfsMetrics.thresholdPercent}{${btrfsMetrics.hostLabel}="' "$alertScript"; then
              echo "alert script's ${btrfsMetrics.thresholdPercent} occurrence has no immediate ${btrfsMetrics.hostLabel} label match" >&2
              exit 1
            fi
            touch "$out"
          '';
    };
}
