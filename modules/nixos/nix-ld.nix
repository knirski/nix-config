# NixOS aspect: FHS-compatible dynamic linker for running unpatched binaries.
#
# nix-ld provides `/lib/ld-linux-x86-64.so.2` and common library paths so
# pre-built Linux binaries (tarball downloads, game launchers, IDE binaries)
# work on NixOS without manual patching.  A general-purpose capability —
# toggle it independently per host rather than bundling with a role aspect.
#
# Docs: https://nixos.org/manual/nixos/stable/#sec-nix-ld
{
  aspects.nixos.nix-ld = { pkgs, ... }: {
    programs.nix-ld = {
      enable = true;
      # In addition to the nix-ld built-in library set (glibc, zlib, stdenv
      # basics), include common libraries that third-party binaries expect.
      libraries = with pkgs; [
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cairo
        cups
        curl
        dbus
        expat
        fontconfig
        freetype
        fuse3
        gdk-pixbuf
        glib
        gtk3
        icu
        libglvnd
        libgpg-error
        libnotify
        libpulseaudio
        libxkbcommon
        libxml2
        mesa
        nspr
        nss
        pango
        pipewire
        python3
        sqlite
        systemd
        util-linux
        xorg.libICE
        xorg.libSM
        xorg.libX11
        xorg.libXau
        xorg.libxcb
        xorg.libXcomposite
        xorg.libXcursor
        xorg.libXdamage
        xorg.libXdmcp
        xorg.libXext
        xorg.libXfixes
        xorg.libXi
        xorg.libXinerama
        xorg.libXrandr
        xorg.libXrender
        xorg.libXt
        xorg.libXtst
        xorg.libXv
        xorg.libXxf86vm
        xorg.libpciaccess
        xz
        zlib
      ];
    };
  };
}
