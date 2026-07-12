# Machine-readable enforcement of Soyo's guest-service resource policy.
#
# Keep this inventory explicit: classifying generated systemd units by name or
# shape would produce false positives and let a renamed guest silently escape
# review. Blocky and dnsmasq are intentionally absent because they are Soyo's
# two critical roles; OpenSSH and core boot/network units are operator/recovery
# infrastructure rather than hosted guest workloads.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      services = inputs.self.nixosConfigurations.soyo.config.systemd.services;
      soyoConfig = inputs.self.nixosConfigurations.soyo.config;

      guestUnits = [
        # Observability guests.
        "alloy"
        "grafana"
        "grafana-alert-setup"
        "lan-inventory-exporter"
        "loki"
        "prometheus"
        "prometheus-blackbox-exporter"
        "prometheus-dnsmasq-exporter"
        "prometheus-node-exporter"
        "tempo"

        # Backup and low-priority maintenance guests.
        "btrbk-soyo"
        "nix-store-optimise"
        "restic-backup-metric-bootstrap"
        "restic-backups-soyo"

        # Remote administration must not contend with DNS or DHCP either.
        "tailscale-auth"
        "tailscaled"
      ]
      ++ pkgs.lib.optionals soyoConfig.lanAppliance.services.maintenance.enable [
        "btrfs-scrub"
        "free-space-check"
        "ntfy-failure@"
      ];

      validate =
        exists: serviceConfig:
        let
          memoryMax = serviceConfig.MemoryMax or null;
          cpuQuota = serviceConfig.CPUQuota or null;
          nice = serviceConfig.Nice or null;
          ioWeight = serviceConfig.IOWeight or null;
          positiveMemory =
            if builtins.isInt memoryMax then
              memoryMax > 0
            else if builtins.isString memoryMax then
              builtins.match "^[1-9][0-9]*([KMGTPE]B?)?$" memoryMax != null
            else
              false;
          positiveCpuQuota =
            builtins.isString cpuQuota && builtins.match "^([1-9][0-9]*)([.][0-9]+)?%$" cpuQuota != null;
          validNice = nice == null || (builtins.isInt nice && nice >= -20 && nice <= 19);
          validIoWeight = ioWeight == null || (builtins.isInt ioWeight && ioWeight >= 1 && ioWeight <= 10000);
          loweredPriority =
            (builtins.isInt nice && nice > 0 && nice <= 19)
            || (builtins.isInt ioWeight && ioWeight >= 1 && ioWeight < 100);
          errors =
            pkgs.lib.optional (!exists) "unit is missing"
            ++ pkgs.lib.optional (!positiveMemory) "MemoryMax is not a positive finite size"
            ++ pkgs.lib.optional (!positiveCpuQuota) "CPUQuota is not a positive percentage"
            ++ pkgs.lib.optional (!validNice) "Nice is outside systemd's -20..19 range"
            ++ pkgs.lib.optional (!validIoWeight) "IOWeight is outside systemd's 1..10000 range"
            ++ pkgs.lib.optional (!loweredPriority) "neither Nice nor IOWeight lowers priority";
        in
        errors;

      inspect =
        unit:
        let
          exists = builtins.hasAttr unit services;
        in
        {
          inherit unit;
          errors = validate exists (if exists then services.${unit}.serviceConfig else { });
        };

      failures = builtins.filter (result: result.errors != [ ]) (map inspect guestUnits);
      # Negative controls keep the validator itself honest. Each fixture has
      # otherwise-valid limits and exactly one deliberately meaningless value.
      invalidFixtures = [
        {
          MemoryMax = "0";
          CPUQuota = "10%";
          Nice = 10;
        }
        {
          MemoryMax = "64M";
          CPUQuota = "0%";
          Nice = 10;
        }
        {
          MemoryMax = "64M";
          CPUQuota = "10%";
          Nice = 20;
        }
        {
          MemoryMax = "64M";
          CPUQuota = "10%";
          IOWeight = 0;
        }
      ];
      invalidFixturesRejected = builtins.all (
        serviceConfig: validate true serviceConfig != [ ]
      ) invalidFixtures;
      failureText = pkgs.lib.concatMapStringsSep "\n" (
        result: "${result.unit}: ${pkgs.lib.concatStringsSep "; " result.errors}"
      ) failures;
    in
    {
      checks.soyo-guest-isolation =
        pkgs.runCommand "soyo-guest-isolation-test"
          {
            failed = if failures == [ ] && invalidFixturesRejected then "0" else "1";
            inherit failureText;
            passAsFile = [ "failureText" ];
          }
          ''
              if [ "$failed" != 0 ]; then
                echo "ERROR: Soyo guest service isolation policy failed:" >&2
            cat "$failureTextPath" >&2
            if [ ! -s "$failureTextPath" ]; then
              echo "validator accepted an invalid negative-control fixture" >&2
            fi
                exit 1
              fi
              touch "$out"
          '';
    };
}
