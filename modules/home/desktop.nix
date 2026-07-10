{
  aspects.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        wl-clipboard
        imv
        mpv
        bitwarden-desktop
        zed-editor
      ];
    };
}
