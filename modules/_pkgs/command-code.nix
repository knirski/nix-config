# Package: command-code — AI coding agent that learns your coding taste.
#
# Fetches the pre-built npm tarball (dist/ ships compiled JS, no tsc needed)
# and installs it as the `cmdc` CLI tool via buildNpmPackage so that all
# runtime dependencies are available in the Nix store and survive
# nixos-rebuild (no bare `npm i -g`).
#
# The sharp native image module needs libvips headers during npm install.
# The upstream tarball ships no package-lock.json, so one is vendored in
# command-code-lock/. That lockfile is a real, owned npm dependency tree:
# see docs/security/supply-chain.md's "Dependency automation decisions" for
# how it's reviewed, updated and scanned. The lockfile is refreshed by the
# repository's command-code update script (which also injects the
# vulnerability overrides — see postPatch below) and scanned as-is.
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
  version = "1.53.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/command-code/-/command-code-${version}.tgz";
    hash = "sha512-vjBqxjX8I/TDE4BvPxni3kUXG5w7V/4le3N6A/NVtSwcAObXWviIy/4asbIlE9qXH5NkekTtzNtCOfbDEHcDRg==";
  };

  dontNpmBuild = true;

  postPatch = ''
    cp ${./command-code-lock/package-lock.json} package-lock.json
    sed -i '/^  "devDependencies": {/,/^  }/d' package.json
    # Force the OpenTelemetry packages to fixed versions. sdk-node pins
    # propagator-jaeger at exactly 2.7.1 and otel-cf-workers' nested exporters
    # pin core at 2.0.0/2.7.1 — all vulnerable (GHSA-45rx-2jwx-cxfr,
    # GHSA-8988-4f7v-96qf). The vendored lockfile is generated with these
    # same overrides applied (see scripts/update-command-code.sh); keeping
    # them in package.json too keeps npm ci's consistency check happy.
    sed -i '$s/^}$/,\n  "overrides": {"@opentelemetry\/core":"2.10.0","@opentelemetry\/propagator-jaeger":"2.10.0"}\n}/' package.json
    # Pin js-yaml to the 4.3.2 patch (GHSA-2883-xcg3-v3hh: empty merge
    # sources bypass maxTotalMergeKeys). js-yaml is a direct dependency here,
    # so an npm override triggers EOVERRIDE — pin the declared spec instead.
    # The vendored lockfile is generated with this same pin.
    sed -i 's/"js-yaml": "[^"]*"/"js-yaml": "4.3.2"/' package.json
  '';

  npmDepsHash = "sha256-hDKBgviQotpWzLPr9NFn+nmH38KH3ai3vfSQW+dcn6k=";

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
    # The upstream package ships `cmd`/`cmdc`/`command-code`/`commandcode`
    # bin aliases; this repo standardizes on `cmdc` to avoid the very short
    # `cmd` name colliding with other tools on PATH.
    makeWrapper "${nodejs}/bin/node" "$out/bin/cmdc" \
      --add-flags "$out/lib/node_modules/${pname}/dist/index.mjs"
    ln -s "$out/bin/cmdc" "$out/bin/command-code"
    ln -s "$out/bin/cmdc" "$out/bin/commandcode"

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
