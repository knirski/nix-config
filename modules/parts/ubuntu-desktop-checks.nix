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
# closure, and the built activation package's generated `activate` script
# still installs packages via the `nix-env`/`~/.nix-profile` mechanism that
# docs/install-ubuntu.md's stable zsh path claim depends on (see the
# `installPackages` assertions below) -- a real, falsifiable regression
# guard against a future Home Manager release changing its default install
# path out from under the docs.
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
        # base: modern CLI tooling docs/install-ubuntu.md Step 4 tells the
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
    in
    {
      checks.ubuntu-desktop-invariants =
        assert lib.assertMsg (missingPackages == [ ])
          "ubuntu's evaluated Home Manager closure is missing expected package(s): ${lib.concatStringsSep ", " missingPackages}";
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

            # docs/install-ubuntu.md's optional chsh/`/etc/shells` instructions
            # tell the operator to register `$HOME/.nix-profile/bin/zsh` -- the
            # stable Nix profile symlink, not a raw
            # `/nix/store/<hash>-zsh-x.y.z/bin/zsh` path -- because that's
            # genuinely where standalone HM's own activation script installs
            # `home.packages`/`programs.*`. Rather than asserting a Nix string
            # literal against itself, inspect the *actual built* `activate`
            # script's installPackages logic: it must still branch on whether
            # `~/.nix-profile/manifest.json` exists (the newer `nix profile`
            # bookkeeping file) and, when it does not -- true for any operator
            # who has never separately run `nix profile install` -- fall back
            # to `nix-env -i`, which installs into that user's default Nix
            # profile at `~/.nix-profile`. If a future Home Manager release
            # drops this fallback (e.g. switches unconditionally to `nix
            # profile install` against `~/.local/state/nix/profiles/profile`
            # instead), this check fails loudly instead of leaving the doc's
            # claim to silently go stale.
            activateScript=$(readlink -f "$activation/activate")
            if [ ! -f "$activateScript" ]; then
              echo "expected $activation/activate to exist" >&2
              exit 1
            fi

            if ! grep -q '\.nix-profile/manifest\.json' "$activateScript"; then
              echo "activate script no longer branches on ~/.nix-profile/manifest.json -- docs/install-ubuntu.md's stable zsh path claim may be stale" >&2
              exit 1
            fi

            if ! grep -q 'nix-env -i' "$activateScript"; then
              echo "activate script no longer falls back to 'nix-env -i' (which installs into ~/.nix-profile) -- docs/install-ubuntu.md's stable zsh path claim may be stale" >&2
              exit 1
            fi

            touch "$out"
          '';
    };
}
