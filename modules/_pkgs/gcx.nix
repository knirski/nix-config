# Package: gcx — Grafana CLI
#
# Fetches the pre-built Linux amd64 binary from the GitHub release.
# gcx is a statically-linked Go binary; no runtime dependencies needed.
#
# Updating to a newer version:
#   1. Bump `version` and the `src` URL.
#   2. Remove the `hash` line and set it to `lib.fakeSha256`.
#   3. Run:  nix build .#gcx 2>&1 | grep "got:"
#   4. Copy the printed hash back into the `hash` field.
{
  lib,
  fetchurl,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation rec {
  pname = "gcx";
  version = "0.4.4";

  src = fetchurl {
    url = "https://github.com/grafana/gcx/releases/download/v${version}/gcx_${version}_linux_amd64.tar.gz";
    hash = "sha256-PFApmbgTL6TEJq9amhWz/FyHm5oQ0N7Ls1rHS3EyefE=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp gcx $out/bin/
    runHook postInstall
  '';

  meta = {
    description = "Grafana CLI — query dashboards, alerts, metrics, logs, traces from your terminal";
    homepage = "https://github.com/grafana/gcx";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "gcx";
  };
}
