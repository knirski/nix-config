# Negative fixtures for the Btrfs usage metric contract shared between the
# Prometheus textfile producer (modules/nixos/maintenance.nix) and the
# Grafana alert-rule consumer (lib/observability/grafana-alert-setup.nix).
# See modules/parts/observability-contract-checks.nix, btrfsAlertContractValid.
#
# Each mutation starts from a fixture that satisfies the contract and breaks
# exactly one side of it — the producer's emitted metric name, or the
# consumer's query. None of these should ever validate as correct.
let
  btrfsMetrics = import ../../lib/observability/btrfs-metrics.nix;
in
[
  {
    name = "producer-renames-usage-metric";
    # The historical-shaped bug in reverse: the producer drifts to a name the
    # consumer no longer references.
    mutate =
      fixture:
      fixture
      // {
        producerText =
          builtins.replaceStrings [ btrfsMetrics.usagePercent ] [ "btrfs_util_percent" ]
            fixture.producerText;
      };
  }
  {
    name = "producer-renames-threshold-metric";
    mutate =
      fixture:
      fixture
      // {
        producerText =
          builtins.replaceStrings
            [ btrfsMetrics.thresholdPercent ]
            [
              "btrfs_threshold_pct"
            ]
            fixture.producerText;
      };
  }
  {
    name = "consumer-reintroduces-soyo-prefix";
    # The actual bug this task fixes: the alert expression invents a
    # "soyo_" prefix the producer never emits.
    mutate =
      fixture:
      fixture
      // {
        alertExpr =
          builtins.replaceStrings
            [
              btrfsMetrics.usagePercent
              btrfsMetrics.thresholdPercent
            ]
            [
              "soyo_${btrfsMetrics.usagePercent}"
              "soyo_${btrfsMetrics.thresholdPercent}"
            ]
            fixture.alertExpr;
      };
  }
  {
    name = "consumer-drops-host-label";
    # Correct metric names but no label match at all — a different host's
    # series could satisfy this alert.
    mutate =
      fixture:
      fixture
      // {
        alertExpr = "${btrfsMetrics.usagePercent} > ${btrfsMetrics.thresholdPercent}";
      };
  }
  {
    name = "consumer-drops-label-on-one-side";
    # Both metric names present and one side labeled, but the label is
    # dropped from the *other* occurrence — e.g.
    # `btrfs_usage_percent{host="soyo"} > btrfs_usage_threshold_percent`.
    # A check that only looks for the label substring somewhere in the
    # whole expression would still accept this, even though the unlabeled
    # side could match any host's series.
    mutate =
      fixture:
      fixture
      // {
        alertExpr = "${btrfsMetrics.usagePercent}{${btrfsMetrics.hostLabel}=\"soyo\"} > ${btrfsMetrics.thresholdPercent}";
      };
  }
]
