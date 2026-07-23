# Proves each host's evaluated Home Manager release actually tracks the
# Nixpkgs channel its assembler intends, not just that `nix flake check`
# happens to stay quiet. `nix flake check` only reports the release-mismatch
# *warning* (see modules/home-environment.nix's enableNixpkgsReleaseCheck),
# which a future edit could silence with `home.enableNixpkgsReleaseCheck =
# false` without anyone noticing the underlying wiring broke again.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      # Every Home Manager checkout bakes its own release marker into
      # release.json (read by modules/misc/version.nix as
      # `home.version.release`), independent of whichever Nixpkgs it is later
      # evaluated against. Reading it straight off the flake input -- not off
      # a host's evaluated config -- proves the *input* itself is wired to
      # the Nixpkgs release we expect, before any host-specific mistake could
      # mask that.
      releaseOf = flakeInput: (lib.importJSON (flakeInput + "/release.json")).release;
      homeManagerStableRelease = releaseOf inputs.home-manager-stable;
      homeManagerUnstableRelease = releaseOf inputs.home-manager;
      nixpkgsStableRelease = inputs.nixpkgs.lib.trivial.release;
      nixpkgsUnstableRelease = inputs.nixpkgs-unstable.lib.trivial.release;

      # What each host's assembler actually resolved to at eval time: the
      # release Home Manager reports for itself, and the release its own
      # `pkgs` (the one home-manager.useGlobalPkgs / homeManagerConfiguration
      # actually built against) reports. Equal values is exactly the
      # condition modules/home-environment.nix uses to decide whether to
      # print the mismatch warning.
      soyo = inputs.self.nixosConfigurations.soyo;
      zbook = inputs.self.nixosConfigurations.zbook;
      macbook = inputs.self.darwinConfigurations.macbook;

      nixosHmRelease = host: host.config.home-manager.users.krzysiek.home.version.release;
      darwinHmRelease = host: host.config.home-manager.users.krzysiek.home.version.release;
      ubuntuHmRelease = inputs.self.homeConfigurations.ubuntu.config.home.version.release;

      testResults = {
        # The flake inputs themselves are wired to the intended Nixpkgs
        # release, independent of any host.
        home-manager-stable-input-tracks-nixpkgs-release = homeManagerStableRelease == nixpkgsStableRelease;
        home-manager-input-tracks-nixpkgs-unstable-release =
          homeManagerUnstableRelease == nixpkgsUnstableRelease;
        # The two Home Manager inputs genuinely diverge -- otherwise every
        # test below would trivially pass even if soyo used the wrong input.
        stable-and-unstable-home-manager-releases-diverge =
          homeManagerStableRelease != homeManagerUnstableRelease;

        # Soyo (stable nixpkgs, M1-M4) must resolve Home Manager to the
        # stable input and must not carry a release/Nixpkgs mismatch.
        soyo-home-manager-tracks-stable-input = nixosHmRelease soyo == homeManagerStableRelease;
        soyo-home-manager-matches-its-nixpkgs = nixosHmRelease soyo == soyo.pkgs.lib.trivial.release;

        # zbook, macbook, and ubuntu all track nixpkgs-unstable end to end.
        zbook-home-manager-tracks-unstable-input = nixosHmRelease zbook == homeManagerUnstableRelease;
        zbook-home-manager-matches-its-nixpkgs = nixosHmRelease zbook == zbook.pkgs.lib.trivial.release;

        macbook-home-manager-tracks-unstable-input = darwinHmRelease macbook == homeManagerUnstableRelease;
        macbook-home-manager-matches-its-nixpkgs =
          darwinHmRelease macbook == macbook.pkgs.lib.trivial.release;

        ubuntu-home-manager-tracks-unstable-input = ubuntuHmRelease == homeManagerUnstableRelease;
        ubuntu-home-manager-matches-its-nixpkgs =
          ubuntuHmRelease == inputs.self.homeConfigurations.ubuntu.pkgs.lib.trivial.release;
      };

      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      checks.home-manager-channel-invariants =
        assert
          failed == [ ]
          || throw "Home Manager channel invariant tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "home-manager-channel-invariants-test" { } ''
          touch $out
        '';
    };
}
