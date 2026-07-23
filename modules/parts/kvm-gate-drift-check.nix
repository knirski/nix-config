# Proves the KVM-classified check set lib/testing/kvm-checks.nix declares
# cannot silently drift from what ci.yml's "Strict KVM behavior tests" job
# and the justfile's `test-resilience` recipe actually build. Task C4 fixed
# clipboard-protocols' nondeterminism and ci.yml's resilience job already
# fails closed when /dev/kvm is unavailable, but neither guarantee holds if a
# future edit adds or drops a KVM check in only one of the four places (Nix
# outputs, CI, just, docs) that must agree -- see docs/testing.md ("KVM
# tests") and docs/security/github-settings.md ("Required status checks").
{ inputs, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      inherit (pkgs) lib;
      kvmChecks = import ../../lib/testing/kvm-checks.nix;
      kvmCheckNames = builtins.attrValues kvmChecks;
      expect = lib.concatStringsSep "," kvmCheckNames;

      # Every canonical name must actually be a check this system defines --
      # catches a stale or typo'd entry in lib/testing/kvm-checks.nix itself,
      # which the textual ci.yml/justfile comparison below cannot detect on
      # its own (it only proves ci.yml and justfile agree with whatever this
      # list says, not that the list matches real Nix outputs).
      missingFromNixOutputs = builtins.filter (
        name: !(builtins.hasAttr name config.checks)
      ) kvmCheckNames;

      python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);
      checker = "${inputs.self}/tests/ci/check_kvm_gate.py";
      fixtures = "${inputs.self}/tests/ci/fixtures";
    in
    {
      checks.kvm-gate-drift =
        assert lib.assertMsg (missingFromNixOutputs == [ ])
          "lib/testing/kvm-checks.nix declares check(s) with no matching `checks.<name>` output: ${lib.concatStringsSep ", " missingFromNixOutputs}";
        pkgs.runCommand "kvm-gate-drift" { nativeBuildInputs = [ python ]; } ''
          run() {
            ${python}/bin/python ${checker} --ci-yml "$1/ci.yml" --justfile "$1/justfile" --expect ${expect}
          }

          # The checker itself must accept a matching fixture pair ...
          run "${fixtures}/pass"

          # ... and must reject each known-bad fixture pair with an
          # actionable stderr message, proving a real regression (a name
          # dropped from just, or the whole KVM job missing from ci.yml)
          # would actually fail this check rather than passing silently.
          for rejected in reject-justfile-drops-clipboard reject-ci-missing-job; do
            if run "${fixtures}/$rejected" >stdout 2>stderr; then
              echo "error: kvm-gate-drift fixture unexpectedly passed: $rejected" >&2
              exit 1
            fi
            if [[ ! -s stderr ]]; then
              echo "error: kvm-gate-drift fixture did not produce an actionable error: $rejected" >&2
              exit 1
            fi
          done

          # The real gate: this repository's actual ci.yml and justfile must
          # build exactly the checks lib/testing/kvm-checks.nix declares.
          ${python}/bin/python ${checker} \
            --ci-yml ${inputs.self}/.github/workflows/ci.yml \
            --justfile ${inputs.self}/justfile \
            --expect ${expect}

          touch "$out"
        '';
    };
}
