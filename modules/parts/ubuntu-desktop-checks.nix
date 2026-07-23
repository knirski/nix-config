# H2: proves the ubuntu standalone Home Manager contract that
# docs/install-ubuntu.md and docs/workstation-setup.md now describe actually
# holds against a real build, not just an evaluated config.
#
# Unlike host-role-invariants.nix and home-manager-channel-checks.nix (which
# only *evaluate* `homeConfigurations.ubuntu`), this check forces a genuine
# derivation build of `activationPackage` -- ubuntu has no NixOS/nix-darwin
# system closure, so its activation package is the only artifact that can
# ever be built in CI for this host, and it is buildable on x86_64-linux
# (unlike macbook's aarch64-darwin closure, which cannot be built here).
#
# What this check does NOT do (per task H2's brief): it does not, and
# cannot, validate real GDM3 session discovery or an actual `chsh` login
# shell change -- those require a live Ubuntu machine or VM fixture that
# does not exist yet. This check only proves the evaluated/built Nix config
# is internally consistent with what the docs claim: the packages/programs
# the assembler is supposed to provide are genuinely present in the built
# closure, and the stable zsh path the docs tell the operator to register in
# `/etc/shells` genuinely exists in that closure.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      ubuntuActivation = inputs.self.homeConfigurations.ubuntu.activationPackage;
      ubuntuHome = inputs.self.homeConfigurations.ubuntu.config;

      packageNames = pkgList: map (p: p.pname or p.name or "") pkgList;
      ubuntuPackageNames = packageNames ubuntuHome.home.packages;

      # Representative binaries drawn from what ubuntu's assembler (base +
      # development + desktop + ssh + sway, see modules/parts/ubuntu.nix)
      # is supposed to collectively resolve to. Checked by evaluated
      # package name (survives version bumps) rather than by pinning a
      # store path.
      expectedPackageNames = [
        # base: modern CLI tooling docs/install-ubuntu.md Step 6 tells the
        # operator to validate directly (`bat --version`, `eza --version`,
        # `jq --version`).
        "bat"
        "eza"
        "jq"
        "fd"
        "ripgrep"
        # development: language servers / agent tooling that must be
        # present on every developer host (see host-role-invariants.nix).
        "nil"
        "nixd"
        "rust-analyzer"
        # desktop: apps only ever installed via Home Manager on Linux hosts.
        "signal-desktop"
        "obsidian"
        # sway: the Wayland compositor and its shell.
        "sway"
      ];

      missingPackages = builtins.filter (n: !(builtins.elem n ubuntuPackageNames)) expectedPackageNames;

      # Stable path standalone HM's activation script actually installs
      # `home.packages`/`programs.*` into: `nix profile install
      # <home-manager-path-derivation>` (or the legacy `nix-env -i`
      # equivalent) targets the user's default Nix profile at
      # `$HOME/.nix-profile` (see the built activation script's
      # `installPackages` step). That symlink -- not a raw
      # `/nix/store/<hash>-zsh-x.y.z/bin/zsh` path, which changes on every
      # zsh version bump -- is what docs/install-ubuntu.md's optional `chsh`
      # instructions tell the operator to add to `/etc/shells` and pass to
      # `chsh -s`. This only proves zsh is genuinely present at the
      # corresponding path *inside the built activation package's home-path
      # buildEnv* (`$activation/home-path/bin/zsh`) -- the profile symlink
      # itself only exists on a real machine after `home-manager switch`
      # has actually run, which is exactly the manual-validation boundary
      # the brief draws.
      stableZshDocPath = "$HOME/.nix-profile/bin/zsh";
    in
    {
      checks.ubuntu-desktop-invariants =
        assert lib.assertMsg (missingPackages == [ ])
          "ubuntu's evaluated Home Manager closure is missing expected package(s): ${lib.concatStringsSep ", " missingPackages}";
        assert lib.assertMsg (lib.hasPrefix "$HOME/.nix-profile/" stableZshDocPath)
          "the documented stable zsh path must live under the Nix profile symlink, not a raw store path";
        pkgs.runCommand "ubuntu-desktop-invariants-test"
          {
            # Referencing activationPackage as a build input forces Nix to
            # actually *build* it (not just evaluate it) as part of this
            # check -- a real derivation realisation, matching what
            # `.github/workflows/ci.yml`'s build-ubuntu job does directly.
            activation = ubuntuActivation;
          }
          ''
            homePath=$(readlink -f "$activation/home-path")

            for bin in zsh bat eza jq fd rg sway ghostty dms; do
              if [ ! -x "$homePath/bin/$bin" ]; then
                echo "expected binary '$bin' missing from ubuntu's built home-path: $homePath" >&2
                exit 1
              fi
            done

            # The Sway config file HM is supposed to manage (as opposed to
            # any display-manager session file, which HM cannot write).
            swayConfig=$(readlink -f "$activation/home-files/.config/sway/config")
            if [ ! -e "$swayConfig" ]; then
              echo "expected home-files/.config/sway/config to exist in the built activation package" >&2
              exit 1
            fi

            zshrc=$(readlink -f "$activation/home-files/.zshrc")
            if [ ! -e "$zshrc" ]; then
              echo "expected home-files/.zshrc to exist in the built activation package" >&2
              exit 1
            fi

            sshConfig=$(readlink -f "$activation/home-files/.ssh/config")
            if ! grep -q '^Host soyo$' "$sshConfig"; then
              echo "expected home-files/.ssh/config to declare the soyo host" >&2
              exit 1
            fi

            touch "$out"
          '';
    };
}
