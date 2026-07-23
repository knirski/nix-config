# Bats provides isolated setup/teardown and named command-level contracts while
# keeping the applications black boxes. Its native TAP stream remains in build
# logs; no JUnit artifact is produced because CI does not consume one.
_: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.packages) healthcheck recover-secrets set-tailscale-keys;
      fake =
        name: source:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [ pkgs.coreutils ];
          text = builtins.readFile source;
        };
      fakeSsh = fake "ssh" ../../tests/scripts/fixtures/fake-ssh.bash;
      fakeDig = fake "dig" ../../tests/scripts/fixtures/fake-dig.bash;
      fakeRage = fake "rage" ../../tests/scripts/fixtures/fake-rage.bash;
      fakeNix = fake "nix" ../../tests/scripts/fixtures/fake-nix.bash;
      fakeStat = fake "stat" ../../tests/scripts/fixtures/fake-stat.bash;
      # No runtimeInputs: fake "sudo" only needs to `exec "$@"`, and
      # writeShellApplication prepends any runtimeInputs' bin directories
      # onto PATH before that exec runs. Giving it coreutils (like every
      # other fixture) would put the *real* coreutils stat ahead of
      # tests/scripts/fixtures/fake-stat.bash on PATH, silently defeating
      # the fake for the one command this fake-sudo is meant to pass
      # through to.
      fakeSudo = pkgs.writeShellApplication {
        name = "sudo";
        runtimeInputs = [ ];
        text = builtins.readFile ../../tests/scripts/fixtures/fake-sudo.bash;
      };
      testSubject =
        name: runtimeInputs: source:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          excludeShellChecks = pkgs.lib.optional (name == "healthcheck-test-subject") "SC2029";
          text = builtins.readFile source;
        };
      healthcheckTest = testSubject "healthcheck-test-subject" [
        fakeDig
        fakeSsh
        pkgs.gnugrep
      ] ../../scripts/healthcheck.sh;
      recoverSecretsTest = testSubject "recover-secrets-test-subject" [
        fakeRage
        pkgs.coreutils
        pkgs.git
      ] ../../scripts/recover-secrets.sh;
      setTailscaleKeysTest = testSubject "set-tailscale-keys-test-subject" [
        fakeNix
        fakeRage
        pkgs.coreutils
        pkgs.git
      ] ../../scripts/set-tailscale-keys.sh;
    in
    {
      checks.script-contracts =
        pkgs.runCommand "script-contracts"
          {
            nativeBuildInputs = with pkgs; [
              bats
              coreutils
              diffutils
              findutils
              git
              gnugrep
              shellcheck
            ];
          }
          ''
            export ORIGINAL_PATH="$PATH"
            export PACKAGED_HEALTHCHECK=${pkgs.lib.getExe healthcheck}
            export PACKAGED_RECOVER_SECRETS=${pkgs.lib.getExe recover-secrets}
            export PACKAGED_SET_TAILSCALE_KEYS=${pkgs.lib.getExe set-tailscale-keys}
            export HEALTHCHECK=${pkgs.lib.getExe healthcheckTest}
            export RECOVER_SECRETS=${pkgs.lib.getExe recoverSecretsTest}
            export SET_TAILSCALE_KEYS=${pkgs.lib.getExe setTailscaleKeysTest}
            export FAKE_SSH=${pkgs.lib.getExe fakeSsh}
            export FAKE_DIG=${pkgs.lib.getExe fakeDig}
            export FAKE_RAGE=${pkgs.lib.getExe fakeRage}
            export FAKE_NIX=${pkgs.lib.getExe fakeNix}
            export FAKE_STAT=${pkgs.lib.getExe fakeStat}
            export FAKE_SUDO=${pkgs.lib.getExe fakeSudo}
            # Raw (unpackaged) script source, used by the SSH-free
            # backup-freshness-probe unit tests to extract and execute the
            # real embedded shell logic directly (no SSH, no fake-ssh).
            export HEALTHCHECK_SRC=${../../scripts/healthcheck.sh}
            export HEALTHCHECK_SSH="$FAKE_SSH"
            export HEALTHCHECK_DIG="$FAKE_DIG"
            export RECOVER_SECRETS_RAGE="$FAKE_RAGE"
            export SET_TAILSCALE_KEYS_RAGE="$FAKE_RAGE"
            export SET_TAILSCALE_KEYS_NIX="$FAKE_NIX"
            shellcheck --shell=bash ${../../tests/scripts/test-helper.bash}
            bats --tap ${../../tests/scripts}
            touch "$out"
          '';
    };
}
