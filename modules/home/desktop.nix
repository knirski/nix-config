{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          mpv
          bitwarden-desktop
          spotify
          zed-editor
        ]
        ++ lib.optionals stdenv.isLinux [
          wl-clipboard
          loupe
          freetube
          signal-desktop
        ];
    };
}
