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
      ];

      # Catppuccin COSMIC theme — clone as config files (they're just RON)
      home.file."catppuccin-cosmic" = {
        recursive = true;
        source = pkgs.fetchFromGitHub {
          owner = "catppuccin";
          repo = "cosmic-desktop";
          rev = "95e81098042dd2102f0b258f6990f886c5759692";
          hash = "sha256-NAQnHS+XrMJ/rPgSS5nEQOMBhQtF6mP1i/0QP5arQ64=";
        };
        target = ".config/cosmic/themes/catppuccin";
      };
    };
}
