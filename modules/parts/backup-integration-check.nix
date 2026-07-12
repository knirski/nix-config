# Restic verification has two layers:
#   1. a fast raw-restic check proves byte and repository integrity semantics;
#   2. a VM uses the real backup aspect to prove systemd cleanup metrics and
#      failure handoff behavior without contacting the production NAS.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      backup = config.aspects.nixos.backup;
      runKvmTest = import ../../lib/testing/run-kvm-test.nix { inherit pkgs; };
      rawResticTest = pkgs.writeShellApplication {
        name = "restic-integration-test";
        runtimeInputs = with pkgs; [
          coreutils
          diffutils
          findutils
          gnugrep
          restic
        ];
        text = builtins.readFile ../../tests/backup/restic-integration.sh;
      };
    in
    {
      checks = {
        backup-restic-integration = pkgs.runCommand "backup-restic-integration" { } ''
          export TMPDIR="$NIX_BUILD_TOP"
          ${rawResticTest}/bin/restic-integration-test "$TMPDIR/restic-test"
          test -e "$TMPDIR/restic-test/passed"
          touch "$out"
        '';

        backup-unit-vm = runKvmTest {
          name = "backup-unit-vm";
          globalTimeout = 180;

          nodes.machine =
            { lib, pkgs, ... }:
            {
              imports = [ backup ];

              lanAppliance.services.backup = {
                enable = true;
                hostName = "fixture";
                enablePromMetrics = true;
                restic = {
                  repository = "/var/lib/restic-fixture/repository";
                  passwordFile = "/run/restic-fixture/password";
                  paths = [ "/var/lib/restic-fixture/source" ];
                  exclude = [ ];
                  timerConfig = { };
                  pruneOpts = [ ];
                  checkOpts = [ "--read-data" ];
                };
              };

              # Exercise the same systemd OnFailure boundary as production,
              # but capture locally: no token, topic, URL, or network request.
              systemd.services."restic-backups-fixture".unitConfig.OnFailure =
                "backup-failure-capture@%N.service";
              systemd.services."backup-failure-capture@" = {
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart =
                    lib.getExe (
                      pkgs.writeShellApplication {
                        name = "capture-backup-failure";
                        runtimeInputs = [ pkgs.coreutils ];
                        text = ''
                          set -eu
                          printf '%s\n' "$1" > /run/backup-failure-handoff
                        '';
                      }
                    )
                    + " %i";
                };
              };

              environment.systemPackages = [ pkgs.restic ];
            };

          testScript = ''
            start_all()
            machine.succeed("grep -qw kvm-clock /sys/devices/system/clocksource/clocksource0/available_clocksource")
            machine.wait_for_unit("multi-user.target")

            with subtest("successful real unit writes a successful metric"):
                machine.succeed("install -d /run/restic-fixture /var/lib/restic-fixture/source/nested")
                machine.succeed("printf 'fixture password\\n' > /run/restic-fixture/password")
                machine.succeed("printf 'payload\\n' > /var/lib/restic-fixture/source/nested/file")
                machine.succeed("systemctl start restic-backups-fixture.service")
                machine.succeed("grep -Fx 'restic_backup_ran 1' /var/lib/prometheus/textfiles/backup.prom")
                machine.succeed("grep -Fx 'restic_backup_success 1' /var/lib/prometheus/textfiles/backup.prom")

            with subtest("wrong password reports failure and invokes the local handoff"):
                machine.succeed("printf 'wrong password\\n' > /run/restic-fixture/password")
                machine.fail("systemctl start restic-backups-fixture.service")
                machine.wait_until_succeeds("grep -Fx 'restic_backup_success 0' /var/lib/prometheus/textfiles/backup.prom")
                machine.wait_until_succeeds("grep -Fx 'restic-backups-fixture' /run/backup-failure-handoff")
                machine.succeed("journalctl -u restic-backups-fixture.service --no-pager | grep -Eiq 'password|decrypt|key|failed'")
                machine.fail("journalctl -u restic-backups-fixture.service --no-pager | grep -F 'fixture password'")
                machine.fail("journalctl -u backup-failure-capture@restic-backups-fixture.service --no-pager | grep -F 'wrong password'")

            with subtest("a later success supersedes the failure metric"):
                machine.succeed("printf 'fixture password\\n' > /run/restic-fixture/password")
                machine.succeed("systemctl reset-failed restic-backups-fixture.service")
                machine.succeed("systemctl start restic-backups-fixture.service")
                machine.succeed("grep -Fx 'restic_backup_success 1' /var/lib/prometheus/textfiles/backup.prom")
          '';
        };
      };
    };
}
