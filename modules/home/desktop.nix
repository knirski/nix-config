{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      programs.zed-editor.enable = true;

      home.packages =
        with pkgs;
        [
          mpv
          bitwarden-desktop
          spotify
        ]
        ++ lib.optionals stdenv.isLinux [
          wl-clipboard
          loupe
          freetube
          signal-desktop
        ];
    };
}
