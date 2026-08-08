# Package: command-code — AI coding agent that learns your coding taste.
#
# Fetches the pre-built npm tarball (dist/ ships compiled JS, no tsc needed)
# and installs it as the `cmd` CLI tool via buildNpmPackage so that all
# runtime dependencies are available in the Nix store and survive
# nixos-rebuild (no bare `npm i -g`).
#
# The sharp native image module needs libvips headers during npm install.
# The upstream tarball ships no package-lock.json, so one is vendored in
# command-code-lock/. That lockfile is a real, owned npm dependency tree:
# see docs/security/supply-chain.md's "Dependency automation decisions" for
# how it's reviewed, updated and scanned. The lockfile is refreshed by the
# repository's command-code update script and scanned as-is.
#
# Ref: https://nixos.org/manual/nixpkgs/stable/#buildNpmPackage
#
# Updating to a newer version: run `just update-command-code <version>`
# (scripts/update-command-code.sh). It fetches the upstream tarball, prints
# the `fetchurl` hash, regenerates command-code-lock/package-lock.json with
# the same devDeps-stripping transformation applied here, and prints the
# `npmDepsHash` a human pastes below -- it does
# not edit this file itself, touch flake.lock, or commit anything. After
# pasting the printed `version`/`hash`/`npmDepsHash`, confirm with
# `nix build path:.#command-code`, then review and commit the regenerated
# lockfile. See
# that script's header for the manual dance
# this automates, if you ever need to do it by hand.
{
  lib,
  fetchurl,
  buildNpmPackage,
  nodejs,
  makeWrapper,
  pkg-config,
  vips,
}:

buildNpmPackage rec {
  pname = "command-code";
  version = "1.15.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/command-code/-/command-code-${version}.tgz";
    hash = "sha512-N0NPV45ju7ZliwT1kgN9P2+fI6D1luhRFmnCuOyLC1w9E8ApEYtmOqRtt6fJTyvTmwOEra418xegcT1T4Pc7iw==";
  };

  dontNpmBuild = true;

  postPatch = ''
    cp ${./command-code-lock/package-lock.json} package-lock.json
    sed -i '/^  "devDependencies": {/,/^  }/d' package.json
  '';

  npmDepsHash = "sha256-V1XNUYF6/FLUWXR8f6o+fl6aOrbr6AQTK9BsXAWAFUw=";

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];
  buildInputs = [ vips ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/${pname}"
    cp -r package.json dist node_modules "$out/lib/node_modules/${pname}/"

    mkdir -p "$out/bin"
    makeWrapper "${nodejs}/bin/node" "$out/bin/cmd" \
      --add-flags "$out/lib/node_modules/${pname}/dist/index.mjs"
    ln -s "$out/bin/cmd" "$out/bin/command-code"
    ln -s "$out/bin/cmd" "$out/bin/commandcode"

    runHook postInstall
  '';

  meta = {
    description = "Command Code — coding agent that continuously learns your coding taste";
    homepage = "https://commandcode.ai";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    maintainers = with lib.maintainers; [ ];
  };
}
