# Package: command-code-desktop — GUI desktop app for Command Code.
#
# Fetches the pre-built .deb package from GitHub releases and extracts it
# into the Nix store. The .deb contains an Electron app with the Command Code
# CLI bundled inside.
#
# Ref: https://github.com/CommandCodeAI/desktop
{
  lib,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  stdenv,
  electron,
  nss,
  nspr,
  alsa-lib,
  at-spi2-core,
  cups,
  dbus,
  expat,
  libdrm,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
  mesa,
  pango,
  cairo,
  gtk3,
  glib,
}:

let
  desktopItem = makeDesktopItem {
    name = "command-code-desktop";
    exec = "command-code-desktop %U";
    icon = "command-code-desktop";
    comment = "Desktop App For Command Code — AI coding agent";
    desktopName = "Command Code";
    categories = [ "Development" ];
    mimeTypes = [ "x-scheme-handler/command-code" ];
  };
in

stdenv.mkDerivation rec {
  pname = "command-code-desktop";
  version = "0.1.20";

  src = fetchurl {
    url = "https://github.com/CommandCodeAI/desktop/releases/download/v${version}/CommandCode-${version}-amd64.deb";
    hash = "sha256-Qhg23fy2m8H+JCY4nxR8BNKtwrVzHLGAcEOYtaIPUng=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
  ];

  buildInputs = [
    electron
    nss
    nspr
    alsa-lib
    at-spi2-core
    cups
    dbus
    expat
    libdrm
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxcb
    mesa
    pango
    cairo
    gtk3
    glib
  ];

  dontBuild = true;
  dontConfigure = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/command-code-desktop
    cp -r opt/Command\ Code/* $out/lib/command-code-desktop/

    mkdir -p $out/bin
    makeWrapper "${electron}/bin/electron" "$out/bin/command-code-desktop" \
      --add-flags "$out/lib/command-code-desktop/resources/app" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}" \
      --set-default ELECTRON_IS_DEV 0 \
      --inherit-argv0

    mkdir -p $out/share/applications
    cp ${desktopItem}/share/applications/command-code-desktop.desktop $out/share/applications/

    runHook postInstall
  '';

  meta = {
    description = "Desktop App For Command Code — AI coding agent";
    homepage = "https://commandcode.ai";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ ];
  };
}
