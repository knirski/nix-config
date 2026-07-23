# Pure-evaluation proof that the reusable backup and observability aspects
# (modules/nixos/backup.nix, modules/nixos/observability.nix) carry no
# appliance-specific (Soyo) values baked into the shared aspect itself.
#
# Soyo's own real evaluated config is already covered elsewhere
# (host-role-invariants.nix, persistence-invariants.nix, and the KVM
# integration tests in backup-integration-check.nix). What's missing there is
# proof that a *different* host — different hostname, different LAN NIC,
# different SFTP target/user, different Grafana bind address — evaluates the
# aspect correctly too, without any of Soyo's identifiers leaking through.
# These fixtures mirror host-role-invariants.nix's baseOnly/darwinBaseOnly
# pattern: a purely-for-evaluation nixosSystem built from just the aspect plus
# host-shaped data, asserted against with plain Nix evaluation.
{ config, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      # Grafana's config wires in agenix-rekey secrets (age.secrets.*.path).
      # The real agenix-rekey module isn't needed to prove the listenAddress
      # and firewall wiring — this stand-in supplies just enough of the
      # option shape (rekeyFile/owner/path) so evaluation doesn't fail on an
      # undefined option in a fixture that has no real secrets.
      fakeAgenix = {
        options.age.secrets = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                rekeyFile = lib.mkOption { type = lib.types.path; };
                owner = lib.mkOption {
                  type = lib.types.str;
                  default = "root";
                };
                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/run/agenix/fixture-secret";
                };
              };
            }
          );
          default = { };
        };
      };

      # A fixture host using a different hostname, NAS FQDN, SFTP user, and
      # host-key policy than Soyo's or zbook's — proves the aspect no longer
      # constructs any of these from hostName or a hardcoded literal.
      backupFixture =
        (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            config.aspects.nixos.backup
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              lanAppliance.services.backup = {
                enable = true;
                hostName = "fixturehost";
                restic = {
                  repository = "sftp:fixture-user@fixture-nas.example.org:/backup/fixturehost";
                  passwordFile = "/run/fixture/restic-password";
                  sshKeyFile = "/run/fixture/ssh-key";
                  sftp = {
                    host = "fixture-nas.example.org";
                    user = "fixture-user";
                    strictHostKeyChecking = "yes";
                    knownHostsFile = "/var/lib/fixture/known_hosts";
                  };
                };
              };
            }
          ];
        }).config;
      backupFixtureExtraOptions = backupFixture.services.restic.backups.fixturehost.extraOptions;
      backupFixtureSftpCommand = lib.findFirst (
        o: lib.hasPrefix "sftp.command=" o
      ) null backupFixtureExtraOptions;

      # Base module list shared by both observability fixtures below — only
      # the Grafana listenAddress differs between them.
      observabilityModules = listenAddress: [
        config.aspects.nixos.observability
        fakeAgenix
        {
          nixpkgs.hostPlatform = "x86_64-linux";
          system.stateVersion = "26.05";
          lanAppliance.services.observability = {
            enable = true;
            # A NIC name that looks nothing like Soyo's enp1s0.
            lanInterface = "eth7";
            openFirewall = true;
            grafana = {
              enable = true;
              inherit listenAddress;
            };
          };
        }
      ];

      # Non-loopback bind address: Grafana should be reachable from the LAN,
      # so the firewall rule for the fixture's own interface should open 3000.
      observabilityFixture =
        (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = observabilityModules "10.9.9.9";
        }).config;

      # Loopback-only bind address: Grafana is unreachable from the LAN, so
      # the firewall rule should NOT open 3000 despite openFirewall = true.
      observabilityLoopbackFixture =
        (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = observabilityModules "127.0.0.1";
        }).config;

      # The neighbor-discovery script's `ip neigh show dev <iface>` invocation
      # is baked into a built writeShellApplication script at ExecStart= — a
      # store path, not a string we can pattern-match without building it.
      # This still isn't a VM test: it's a fast derivation build, mirroring
      # observability-contract-checks.nix's approach of reading real
      # generated artifacts rather than trusting the source.
      neighborScript =
        observabilityFixture.systemd.services.lan-inventory-exporter.serviceConfig.ExecStart;

      testResults = {
        # (a) constructed sftp.command reflects the fixture's own SFTP
        # host/user/policy, not czworaczki/soyo-backup/zbook-backup.
        backup-fixture-sftp-command-present = backupFixtureSftpCommand != null;
        backup-fixture-sftp-command-has-no-soyo-values =
          backupFixtureSftpCommand != null
          && !(lib.hasInfix "czworaczki" backupFixtureSftpCommand)
          && !(lib.hasInfix "soyo-backup" backupFixtureSftpCommand)
          && !(lib.hasInfix "zbook-backup" backupFixtureSftpCommand);
        backup-fixture-sftp-command-uses-fixture-values =
          backupFixtureSftpCommand != null
          && lib.hasInfix "fixture-user@fixture-nas.example.org" backupFixtureSftpCommand
          && lib.hasInfix "-o StrictHostKeyChecking=yes" backupFixtureSftpCommand
          && lib.hasInfix "-o UserKnownHostsFile=/var/lib/fixture/known_hosts" backupFixtureSftpCommand;

        # (b) firewall/neighbor-discovery interface reflects the fixture's
        # own NIC name, not enp1s0.
        observability-fixture-firewall-uses-own-interface =
          (observabilityFixture.networking.firewall.interfaces.eth7.allowedTCPPorts or [ ]) == [ 3000 ]
          && !(observabilityFixture.networking.firewall.interfaces ? enp1s0);
        observability-loopback-fixture-firewall-stays-closed =
          (observabilityLoopbackFixture.networking.firewall.interfaces.eth7.allowedTCPPorts or [ ]) == [ ];

        # (c) grafana.listenAddress actually changes the evaluated http_addr.
        observability-fixture-grafana-honors-listen-address =
          observabilityFixture.services.grafana.settings.server.http_addr == "10.9.9.9";
        observability-loopback-fixture-grafana-honors-listen-address =
          observabilityLoopbackFixture.services.grafana.settings.server.http_addr == "127.0.0.1";
      };

      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      checks.service-aspect-invariants =
        assert
          failed == [ ]
          || throw "Service aspect (backup/observability) invariant tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "service-aspect-invariants-test" { inherit neighborScript; } ''
          if ! grep -q 'neigh show dev eth7' "$neighborScript"; then
            echo "expected fixture lan-inventory-exporter script to query eth7" >&2
            exit 1
          fi
          if grep -q 'enp1s0' "$neighborScript"; then
            echo "fixture lan-inventory-exporter script leaked Soyo's enp1s0" >&2
            exit 1
          fi
          touch $out
        '';
    };
}
