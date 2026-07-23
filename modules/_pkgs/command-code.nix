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
# how it's reviewed, updated and scanned, and command-code-lock/
# opentelemetry-overrides.json for the single source of truth for the
# security override applied below.
#
# Ref: https://nixos.org/manual/nixpkgs/stable/#buildNpmPackage
#
# Updating to a newer version: run `just update-command-code <version>`
# (scripts/update-command-code.sh). It fetches the upstream tarball, prints
# the `fetchurl` hash, regenerates command-code-lock/package-lock.json with
# the same devDeps-stripping and OpenTelemetry-override transformation
# applied here, and prints the `npmDepsHash` a human pastes below -- it does
# not edit this file itself, touch flake.lock, or commit anything. After
# pasting the printed `version`/`hash`/`npmDepsHash`, confirm with
# `nix build path:.#command-code` and `nix build
# path:.#checks.x86_64-linux.command-code-security`, then review and commit
# the regenerated lockfile. See that script's header for the manual dance
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

let
  # Data, not code: see command-code-lock/opentelemetry-overrides.json for
  # why this list is the single place to add/remove a dependency-range bump.
  opentelemetryOverrides =
    (builtins.fromJSON (builtins.readFile ./command-code-lock/opentelemetry-overrides.json)).overrides;
  overrideSedArgs = lib.concatMapStringsSep " " (
    o: "-e 's|\"${o.package}\": \"[^\"]*\"|\"${o.package}\": \"${o.range}\"|'"
  ) opentelemetryOverrides;
in
buildNpmPackage rec {
  pname = "command-code";
  version = "0.52.3";

  src = fetchurl {
    url = "https://registry.npmjs.org/command-code/-/command-code-${version}.tgz";
    hash = "sha512-y9rkCblT3uFBfuSOwqix8lRLx9HrcogFng0A0xlagFfwT13ZNOmxe8HMH9/3Ckm3f+Q899XjuZzpg+EAHzr19Q==";
  };

  dontNpmBuild = true;

  postPatch = ''
    cp ${./command-code-lock/package-lock.json} package-lock.json
    sed -i '/^  "devDependencies": {/,/^  }/d' package.json
    # Bump OpenTelemetry deps to fix CVE-2026-54285 (GHSA-8988-4f7v-96qf).
    # The exact package/range pairs come from command-code-lock/
    # opentelemetry-overrides.json (see above) so this list can never drift
    # from what scripts/update-command-code.sh and the security check use.
    sed -i ${overrideSedArgs} package.json
  '';

  npmDepsHash = "sha256-vXqNR0orxegO+cZs/n7VSuaZMwuTA2geKB1kP3U+ToQ=";

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
