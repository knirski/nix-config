# Proves command-code's OpenTelemetry CVE-2026-54285 (GHSA-8988-4f7v-96qf)
# override is actually present in the built, resolved dependency tree -- not
# merely that modules/_pkgs/command-code.nix's postPatch source claims to
# apply it. This is the offline half of command-code's supply-chain
# coverage (see docs/security/supply-chain.md); the network-dependent OSV
# scan over the vendored lockfile lives only in the scheduled
# .github/workflows/security-scan.yml, never here.
#
# Both the real check below and the negative fixtures under
# tests/security/command-code-overrides/{pass,reject-*}/ run the identical
# tests/security/check_command_code_overrides.py predicate, so a vulnerable
# resolved version or a dropped override is provably caught by this check,
# not just documented as intended behavior.
{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (pkgs) lib;
      # Unfree-allowing pkgs, mirroring packages.command-code in
      # perSystem.nix -- this check must build the exact same derivation
      # exposed there.
      pkgs' = import inputs.nixpkgs {
        localSystem = { inherit system; };
        config.allowUnfree = true;
        overlays = [ ];
      };
      commandCode = pkgs'.callPackage ../../modules/_pkgs/command-code.nix { };
      verifier = ../../tests/security/check_command_code_overrides.py;
      overridesJson = ../../modules/_pkgs/command-code-lock/opentelemetry-overrides.json;
      fixturesDir = ../../tests/security/command-code-overrides;
      python = lib.getExe pkgs.python3;
    in
    {
      checks.command-code-security = pkgs.runCommand "command-code-security" { } ''
        echo "== smoke test: cmd --version =="
        "${commandCode}/bin/cmd" --version

        echo "== verifying resolved OpenTelemetry override versions (real build) =="
        ${python} ${verifier} \
          "${commandCode}/lib/node_modules/command-code/node_modules" \
          ${overridesJson}

        echo "== proving the verifier itself accepts a satisfied fixture and rejects unsatisfied ones =="
        ${python} ${verifier} "${fixturesDir}/pass/node_modules" ${overridesJson}

        for rejected in "${fixturesDir}"/reject-*; do
          if ${python} ${verifier} "$rejected/node_modules" ${overridesJson} >stdout 2>stderr; then
            echo "error: override-verification fixture unexpectedly passed: $rejected" >&2
            exit 1
          fi
          if [[ ! -s stderr ]]; then
            echo "error: fixture did not produce an actionable error: $rejected" >&2
            exit 1
          fi
          cat stderr
        done

        touch "$out"
      '';
    };
}
