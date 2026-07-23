# Limine's boot menu and ESP kernel/initrd copies grow by one entry per
# deploy unless bounded. `boot.loader.limine.maxGenerations` caps that growth,
# but it is easy to accidentally drop (refactor) or set to something useless
# (0, null, or a value so large it defeats the point). This is a pure
# predicate test, mirroring the lightweight style of
# modules/parts/reservation-checks.nix: it evaluates the real per-host option
# for the positive case, and exercises fixture values for the negative cases
# rather than re-evaluating a whole NixOS closure per mutation.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      # Documented upper bound from docs/update-and-rollback.md: Soyo and
      # zbook both keep at most this many old generations bootable via the
      # Limine menu. `nix.gc` (modules/nixos/maintenance.nix) separately
      # reclaims Nix store space on a 30-day horizon; it does not touch the
      # boot menu, and neither option touches the persisted Secure Boot
      # signing keys under /var/lib/sbctl.
      upperBound = 10;

      soyo = inputs.self.nixosConfigurations.soyo.config;
      zbook = inputs.self.nixosConfigurations.zbook.config;

      # The contract: non-null, a positive integer, and no greater than the
      # documented upper bound. `builtins.isInt` rejects strings/floats/etc;
      # explicitly checking for null first keeps the error path readable
      # (an arithmetic comparison against null throws in Nix).
      withinBound = value: value != null && builtins.isInt value && value > 0 && value <= upperBound;

      testResults = {
        soyo-max-generations-within-bound = withinBound soyo.boot.loader.limine.maxGenerations;
        zbook-max-generations-within-bound = withinBound zbook.boot.loader.limine.maxGenerations;

        # Negative fixtures: values that must never pass, proving the
        # predicate itself (not just today's config) rejects regressions.
        rejects-null = !(withinBound null);
        rejects-zero = !(withinBound 0);
        rejects-negative = !(withinBound (-1));
        rejects-excessive = !(withinBound (upperBound + 1));
        rejects-non-integer = !(withinBound "10");
      };

      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      checks.boot-generation-invariants =
        assert
          failed == [ ]
          || throw "Boot generation invariant tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "boot-generation-invariants-test" { } ''
          touch $out
        '';
    };
}
