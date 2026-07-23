# H1: proves the macbook Aerospace/terminal/package-matrix contract holds
# against the real evaluated configuration, not just what the source or the
# docs claim.
#
#   - Every executable Aerospace's keybindings invoke via `exec-and-forget`
#     (modules/home/aerospace.nix) must resolve to either a package actually
#     present in macbook's real evaluated Home Manager closure, or a
#     documented macOS system executable (`macosSystemExecutables` below) --
#     never a floating, undefined command name like the historical `kitty`
#     binding, which was never installed anywhere for macbook.
#   - docs/workstation-setup.md's Tool Availability Matrix rows for Firefox,
#     Bitwarden, Signal, and Obsidian must match the real evaluated closures
#     of all three hosts the matrix claims to describe. This parses the
#     actual table cells out of the doc (not a hand-duplicated summary living
#     only in this file), so an editor who changes the table without
#     re-checking eval, or changes eval without re-checking the table, fails
#     this check either way -- the same "documented claim vs. real evaluated
#     state" shape as host-role-invariants.nix (R2) and
#     nixpkgs-policy-checks.nix (S4).
#
# Both predicates are proven to actually reject bad input (not just to
# trivially pass) against small inline negative fixtures, following the
# convention set by nixpkgs-policy-checks.nix and kvm-gate-drift-check.nix.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      macbookHome = inputs.self.darwinConfigurations.macbook.config.home-manager.users.krzysiek;
      zbookConfig = inputs.self.nixosConfigurations.zbook.config;
      ubuntuHome = inputs.self.homeConfigurations.ubuntu.config;

      packageNames = pkgList: map (p: p.pname or p.name or "") pkgList;
      macbookPackageNames = packageNames macbookHome.home.packages;

      # ---- (a) Aerospace exec-and-forget target resolution ----

      # Real macOS system executables (not Nix packages) that Aerospace's
      # keybindings are allowed to invoke via exec-and-forget. `open` is
      # macOS's built-in launcher (/usr/bin/open on every real Mac), used
      # here to launch Terminal.app -- an app nix-darwin does not need to
      # (and does not) manage.
      macosSystemExecutables = [ "open" ];

      isExecBinding = cmd: lib.hasPrefix "exec-and-forget " cmd;
      execTarget = cmd: lib.head (lib.splitString " " (lib.removePrefix "exec-and-forget " cmd));

      # True if `cmd` is not an exec-and-forget binding at all (nothing to
      # resolve, e.g. "focus left"), or if its target resolves against the
      # given package-name and system-executable lists.
      execBindingResolves =
        pkgNames: sysExes: cmd:
        !(isExecBinding cmd)
        || builtins.elem (execTarget cmd) sysExes
        || builtins.elem (execTarget cmd) pkgNames;

      aerospaceBindings = macbookHome.programs.aerospace.settings.mode.main.binding;
      unresolvedBindings = lib.filterAttrs (
        _: cmd: !(execBindingResolves macbookPackageNames macosSystemExecutables cmd)
      ) aerospaceBindings;

      # Prove the predicate actually bites: a fabricated binding invoking an
      # uninstalled binary (mirroring the historical `kitty` regression) must
      # be rejected, a non-exec binding must be a trivial pass, and the real
      # fixed binding (`open -a Terminal`) must resolve against the
      # documented system-executable allowlist.
      execFixtureResults = {
        rejects-uninstalled-binary =
          !(execBindingResolves macbookPackageNames macosSystemExecutables "exec-and-forget kitty");
        ignores-non-exec-binding =
          execBindingResolves macbookPackageNames macosSystemExecutables
            "focus left";
        accepts-documented-system-executable =
          execBindingResolves macbookPackageNames macosSystemExecutables
            "exec-and-forget open -a Terminal";
      };
      failedExecFixtures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) execFixtureResults);

      # ---- (b) doc-vs-eval matrix drift for Firefox/Bitwarden/Signal/Obsidian ----

      docText = builtins.readFile ../../docs/workstation-setup.md;
      docLines = lib.splitString "\n" docText;

      symbolToBool =
        sym:
        if sym == "✓" then
          true
        else if sym == "✗" then
          false
        else
          throw "docs/workstation-setup.md matrix cell has an unrecognized symbol: ${sym}";

      # Extract the (zbook, macbook, ubuntu) symbols for a `| **Label** | z | m | u |`
      # matrix row. Matches the real table's column order (see the
      # "| Category | zbook | macbook | ubuntu |" header).
      matrixRow =
        label:
        let
          prefix = "| **${label}** |";
          matches = builtins.filter (l: lib.hasPrefix prefix l) docLines;
          line =
            if builtins.length matches == 1 then
              builtins.head matches
            else
              throw "docs/workstation-setup.md: expected exactly one matrix row for ${label}, found ${toString (builtins.length matches)}";
          m = builtins.match "\\| \\*\\*${label}\\*\\* \\| ([^|]+) \\| ([^|]+) \\| ([^|]+) \\|" line;
        in
        if m == null then
          throw "docs/workstation-setup.md: matrix row for ${label} did not match the expected `| **${label}** | z | m | u |` shape: ${line}"
        else
          map symbolToBool m;

      # Prove the row parser itself distinguishes ✓ from ✗ and rejects
      # garbage, using fabricated lines -- not the real doc -- so this can't
      # trivially pass by matching everything.
      testRowParse =
        label: line:
        let
          m = builtins.match "\\| \\*\\*${label}\\*\\* \\| ([^|]+) \\| ([^|]+) \\| ([^|]+) \\|" line;
        in
        if m == null then null else map symbolToBool m;
      docParserFixtureResults = {
        parses-all-check =
          (testRowParse "X" "| **X** | ✓ | ✓ | ✓ |") == [
            true
            true
            true
          ];
        parses-mixed =
          (testRowParse "X" "| **X** | ✓ | ✗ | ✓ |") == [
            true
            false
            true
          ];
        rejects-malformed-row = (testRowParse "X" "| X | ✓ | ✓ | ✓ |") == null;
        rejects-unrecognized-symbol =
          !(builtins.tryEval (builtins.deepSeq (testRowParse "X" "| **X** | ✓ | ? | ✓ |") true)).success;
      };
      failedDocParserFixtures = builtins.attrNames (
        lib.filterAttrs (_: passed: !passed) docParserFixtureResults
      );

      # Real evaluated presence, per host, for the four apps the matrix
      # claims. zbook/ubuntu/macbook Home Manager closures are compared by
      # package name (pname falling back to name); Firefox is additionally
      # checked against zbook's NixOS-level environment.systemPackages,
      # since it is only ever installed there (aspects.nixos.desktop), never
      # via Home Manager -- macbook and ubuntu have no route to it at all.
      zbookHome = zbookConfig.home-manager.users.krzysiek;
      zbookSystemPackageNames = packageNames zbookConfig.environment.systemPackages;
      hasPkg = home: name: builtins.elem name (packageNames home.home.packages);

      evaluatedMatrix = {
        Firefox = {
          zbook = builtins.elem "firefox" zbookSystemPackageNames;
          macbook = hasPkg macbookHome "firefox";
          ubuntu = hasPkg ubuntuHome "firefox";
        };
        Bitwarden = {
          zbook = hasPkg zbookHome "bitwarden-desktop";
          macbook = hasPkg macbookHome "bitwarden-desktop";
          ubuntu = hasPkg ubuntuHome "bitwarden-desktop";
        };
        Signal = {
          zbook = hasPkg zbookHome "signal-desktop";
          macbook = hasPkg macbookHome "signal-desktop";
          ubuntu = hasPkg ubuntuHome "signal-desktop";
        };
        Obsidian = {
          zbook = hasPkg zbookHome "obsidian";
          macbook = hasPkg macbookHome "obsidian";
          ubuntu = hasPkg ubuntuHome "obsidian";
        };
      };

      matrixDrift = lib.filterAttrs (_: matches: !matches) (
        lib.mapAttrs (
          label: expected:
          let
            docSymbols = matrixRow label;
          in
          docSymbols == [
            expected.zbook
            expected.macbook
            expected.ubuntu
          ]
        ) evaluatedMatrix
      );
    in
    {
      checks.macbook-desktop-invariants =
        assert lib.assertMsg (failedExecFixtures == [ ])
          "Aerospace exec-and-forget resolution fixture(s) failed: ${lib.concatStringsSep ", " failedExecFixtures}";
        assert lib.assertMsg (unresolvedBindings == { })
          "Aerospace binding(s) invoke an executable not present in macbook's evaluated Home Manager closure and not in the documented macOS system-executable allowlist: ${builtins.toJSON unresolvedBindings}";
        assert lib.assertMsg (failedDocParserFixtures == [ ])
          "docs/workstation-setup.md matrix-row parser fixture(s) failed: ${lib.concatStringsSep ", " failedDocParserFixtures}";
        assert lib.assertMsg (matrixDrift == { })
          "docs/workstation-setup.md's Tool Availability Matrix has drifted from the real evaluated configuration for: ${lib.concatStringsSep ", " (lib.attrNames matrixDrift)}";
        pkgs.runCommand "macbook-desktop-invariants" { } ''
          touch "$out"
        '';
    };
}
