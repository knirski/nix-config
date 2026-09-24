# Proves zbook's Sway desktop contract against the real evaluated
# configuration, the way macbook-desktop-checks.nix does for Aerospace: every
# executable a keybinding or startup command launches must resolve to a
# package in zbook's evaluated Home Manager or system closure, or to a
# documented module-provided executable -- never a floating command name like
# the historical `kitty` binding that shipped macbook a terminal it never
# installed.
#
# The resolution predicate is proven to bite against inline negative fixtures,
# following the convention of nixpkgs-policy-checks.nix and
# macbook-desktop-checks.nix.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      zbook = inputs.self.nixosConfigurations.zbook.config;
      zbookHome = zbook.home-manager.users.krzysiek;
      sway = zbookHome.wayland.windowManager.sway;

      # Executable names a package offers that differ from its package name:
      # `dms` comes from dms-shell and is exposed through meta.mainProgram.
      mainProgramOf = p: p.meta.mainProgram or null;
      providedExecutables =
        pkgList:
        lib.concatMap (
          p:
          let
            main = mainProgramOf p;
          in
          [ (p.pname or p.name or "") ] ++ lib.optional (main != null) main
        ) pkgList;

      # Binaries provided by enabled modules rather than by a package-list
      # entry. `swaymsg` ships in the `sway` package (whose mainProgram is
      # just `sway`) installed by aspects.nixos.sway's programs.sway.enable.
      # Nothing else belongs here: adding a name is an explicit decision that
      # the module provides it.
      moduleProvidedExecutables = [ "swaymsg" ];

      allowedExecutables =
        providedExecutables zbookHome.home.packages
        ++ providedExecutables zbook.environment.systemPackages
        ++ moduleProvidedExecutables;

      execTargetOf =
        cmd:
        if lib.hasPrefix "exec " cmd then
          lib.head (lib.splitString " " (lib.removePrefix "exec " cmd))
        else
          null;

      # Keybindings only spawn a process for `exec` commands; Sway executes
      # every `startup` entry, so its first token is the target.
      keybindingTargets = lib.filter (t: t != null) (
        map execTargetOf (lib.attrValues sway.config.keybindings)
      );
      startupTargets = map (entry: lib.head (lib.splitString " " entry.command)) sway.config.startup;
      targets = keybindingTargets ++ startupTargets;

      # Absolute store paths are self-resolving (e.g. the desk-switch
      # wrapper); everything else must be a known executable name.
      resolves = target: lib.hasPrefix "/" target || builtins.elem target allowedExecutables;
      unresolved = lib.filter (target: !(resolves target)) targets;

      fixtures = {
        sway-is-enabled = sway.enable;
        rejects-uninstalled-binary = !(resolves "kitty");
        accepts-installed-package = resolves "ghostty";
        accepts-mainprogram-name = resolves "dms";
        accepts-module-provided-executable = resolves "swaymsg";
        accepts-absolute-store-path = resolves "/nix/store/00000000000000000000000000000000-desk-switch/bin/desk-switch";
        ignores-empty-command = execTargetOf "" == null;
      };
      failedFixtures = builtins.attrNames (lib.filterAttrs (_: ok: !ok) fixtures);
    in
    {
      checks.zbook-desktop-invariants =
        assert lib.assertMsg (
          failedFixtures == [ ]
        ) "zbook desktop invariant fixture(s) failed: ${lib.concatStringsSep ", " failedFixtures}";
        assert lib.assertMsg (unresolved == [ ])
          "zbook Sway keybinding/startup target(s) do not resolve to any evaluated package or documented module-provided executable: ${lib.concatStringsSep ", " unresolved}";
        pkgs.runCommand "zbook-desktop-invariants" { } ''
          touch "$out"
        '';
    };
}
