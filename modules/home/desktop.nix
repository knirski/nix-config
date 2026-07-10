{
  aspects.homeManager.desktop =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        pavucontrol
        brightnessctl
        wl-clipboard
        imv
        mpv
        bitwarden-desktop
        zed-editor
      ];
    };
}
