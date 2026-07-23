# Enforces the package-policy boundary from task S4:
#
#   - Soyo (a headless appliance, the other nixos.base consumer besides
#     zbook) must never pick up an insecure-package allowance. This is a
#     real regression test against nixosConfigurations.soyo's evaluated
#     config, not a read of the source — it would catch someone re-adding
#     `permittedInsecurePackages` to the shared nixos.base aspect, or
#     hardcoding it back into lib/mk-nixpkgs-args.nix's default config.
#   - Every entry in lib/insecure-package-exceptions.nix (the reviewed
#     registry wired into zbook/macbook/ubuntu — see those host assemblers
#     and lib/mk-nixpkgs-args.nix) carries the required structured
#     rationale/owner/review metadata, so a future addition can't slip in
#     as a bare package string with no accountability trail.
#   - zbook, macbook, and ubuntu's actually-evaluated
#     permittedInsecurePackages match the registry exactly — proving the
#     registry is genuinely the single source of truth and not just
#     documentation sitting next to hand-duplicated lists.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      registry = import ../../lib/insecure-package-exceptions.nix;
      registryPackages = map (e: e.package) registry;

      soyoConfig = inputs.self.nixosConfigurations.soyo.config.nixpkgs.config;
      zbookConfig = inputs.self.nixosConfigurations.zbook.config.nixpkgs.config;
      macbookConfig = inputs.self.darwinConfigurations.macbook.config.nixpkgs.config;
      ubuntuPkgsConfig = inputs.self.homeConfigurations.ubuntu.pkgs.config;

      soyoInsecureAllowance = soyoConfig.permittedInsecurePackages or [ ];

      # Pure schema predicate: every field must be present, non-empty, and
      # of the right shape. Run against the real registry (must pass) and
      # against hand-mutated fixtures below (must all fail) — the same
      # "prove the check bites" shape as
      # modules/parts/failure-notification-checks.nix and
      # modules/parts/observability-contract-checks.nix.
      isNonEmptyString = v: builtins.isString v && v != "";
      isIsoDate = v: builtins.isString v && builtins.match "[0-9]{4}-[0-9]{2}-[0-9]{2}" v != null;
      isPositiveInt = v: builtins.isInt v && v > 0;

      requiredFields = [
        "package"
        "knownVulnerability"
        "rationale"
        "owner"
        "reviewed"
        "reviewIntervalDays"
      ];

      insecureExceptionValid =
        entry:
        builtins.all (f: builtins.hasAttr f entry) requiredFields
        && isNonEmptyString (entry.package or null)
        && isNonEmptyString (entry.knownVulnerability or null)
        && isNonEmptyString (entry.rationale or null)
        && isNonEmptyString (entry.owner or null)
        && isIsoDate (entry.reviewed or null)
        && isPositiveInt (entry.reviewIntervalDays or null);

      invalidRegistryEntries = map (e: e.package or "<unnamed>") (
        lib.filter (e: !(insecureExceptionValid e)) registry
      );

      safeFixture = {
        package = "example-package-1.2.3";
        knownVulnerability = "Example package is EOL";
        rationale = "Fixture entry used only to prove the validator rejects mutations of it.";
        owner = "test-owner";
        reviewed = "2026-01-01";
        reviewIntervalDays = 180;
      };
      mutations = import ../../tests/nixpkgs-policy/insecure-exception-mutations.nix;
      mutationAccepted = map (m: m.name) (
        lib.filter (m: insecureExceptionValid (m.mutate safeFixture)) mutations
      );

      # Also prove the validator accepts a *good* synthetic fixture — the
      # mutation list alone can't distinguish "correctly rejects broken
      # entries" from "rejects everything, including well-formed ones".
      safeFixtureValid = insecureExceptionValid safeFixture;

      hostDrift = lib.filterAttrs (_: matches: !matches) {
        zbook = (zbookConfig.permittedInsecurePackages or [ ]) == registryPackages;
        macbook = (macbookConfig.permittedInsecurePackages or [ ]) == registryPackages;
        ubuntu = (ubuntuPkgsConfig.permittedInsecurePackages or [ ]) == registryPackages;
      };
    in
    {
      checks.nixpkgs-policy-invariants =
        assert lib.assertMsg (soyoInsecureAllowance == [ ])
          "soyo's evaluated nixpkgs.config.permittedInsecurePackages is not empty: ${builtins.toJSON soyoInsecureAllowance}";
        assert lib.assertMsg (invalidRegistryEntries == [ ])
          "insecure-package-exceptions.nix has entr(y/ies) missing required rationale/owner/review metadata: ${lib.concatStringsSep ", " invalidRegistryEntries}";
        assert lib.assertMsg safeFixtureValid
          "insecureExceptionValid rejected a well-formed fixture entry (validator is broken, not strict)";
        assert lib.assertMsg (mutationAccepted == [ ])
          "insecure-package exception schema validator accepted negative fixtures: ${lib.concatStringsSep ", " mutationAccepted}";
        assert lib.assertMsg (hostDrift == { })
          "host(s) with permittedInsecurePackages that don't match lib/insecure-package-exceptions.nix: ${lib.concatStringsSep ", " (lib.attrNames hostDrift)}";
        pkgs.runCommand "nixpkgs-policy-invariants" { } ''
          touch "$out"
        '';
    };
}
