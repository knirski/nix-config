## Single source of truth for the Btrfs usage metric names shared between the
## Prometheus textfile producer (modules/nixos/maintenance.nix) and the
## Grafana alert-rule consumer (lib/observability/grafana-alert-setup.nix).
## Plain data, no module system — kept outside modules/ so import-tree never
## sees it, and both sides can `import` it directly.
{
  usagePercent = "btrfs_usage_percent";
  thresholdPercent = "btrfs_usage_threshold_percent";
  hostLabel = "host";
}
