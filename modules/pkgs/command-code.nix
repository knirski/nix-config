# Package: command-code — AI coding agent that learns your coding taste.
#
# Fetches the pre-built npm tarball (dist/ ships compiled JS, no tsc needed)
# and installs it as the `cmd` CLI tool via buildNpmPackage so that all
# runtime dependencies are available in the Nix store and survive
# nixos-rebuild (no bare `npm i -g`).
#
# The sharp native image module needs libvips headers during npm install.
# The upstream tarball ships no package-lock.json, so one is vendored in
# modules/pkgs/command-code-lock/.
#
# Ref: https://nixos.org/manual/nixpkgs/stable/#buildNpmPackage
#
# Updating to a newer version:
#   1. Bump `version` and the `fetchurl` hash (get it from the npm registry
#      via `nix store prefetch-file --hash-type sha512 https://...`).
#   2. Delete `npmDepsHash` and set it to `lib.fakeHash`.
#   3. Run:  nix build .#command-code 2>&1 | grep "got:"
#   4. Copy the printed hash back into `npmDepsHash`.
#   5. The lockfile in `command-code-lock/` was generated from the original
#      upstream tarball after stripping devDeps. To regenerate:
#        tar xzf <tarball> -C /tmp/cc && cd /tmp/cc/package && \
#        sed -i '/"devDependencies": {/,/^  }/d' package.json && \
#        npm install --package-lock-only --ignore-scripts && \
#        cp package-lock.json modules/pkgs/command-code-lock/
#   6. Rebuild with `nix build .#command-code` to confirm.
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
  version = "0.41.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/command-code/-/command-code-${version}.tgz";
    hash = "sha512-HQnzmD0ZF91ImrK8TpIxz/xKVarzHc3CriKRL3mUOCvNeDIQJe3hJZQ5NA0I+v1Q8zZ/k4ooVrNT+bxexN+PUQ==";
  };

  dontNpmBuild = true;

  postPatch = ''
    cp ${./command-code-lock/package-lock.json} package-lock.json
    sed -i '/^  "devDependencies": {/,/^  }/d' package.json
  '';

  npmDepsHash = "sha256-oG6c3Fl927C58fmGYL3ZcTeItAeO7NYnJGKhiFPluBQ=";

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
    platforms = lib.platforms.linux;
    maintainers = with lib.maintainers; [ ];
  };
}
