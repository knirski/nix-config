{
  aspects.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        imv
        mpv
        bitwarden-desktop
        zed-editor
      ];
    };
}
