{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      programs = {
        zed-editor = {
          enable = true;
          extensions = [
            "nix"
            "toml"
            "rust"
            "python"
            "catppuccin"
          ];
          userSettings = {
            theme = {
              mode = "dark";
              dark = "Catppuccin Mocha";
            };
            hour_format = "hour24";
            vim_mode = false;
            auto_update = false;
            terminal = {
              font_family = "JetBrainsMono Nerd Font";
              font_size = 13;
            };
            buffer_font_family = "JetBrainsMono Nerd Font";
            buffer_font_size = 14;
            ui_font_family = "Inter Variable";
            ui_font_size = 14;
          };
        };
      };

      # Manual lid-close inhibitor.  Run `disable-lid` in a terminal before
      # closing the laptop lid to keep the system awake (useful when moving
      # between rooms while media is playing or a download is running).
      # Cancel it with Ctrl+C — the inhibitor is released on script exit.
      home.packages =
        with pkgs;
        [
          mpv
          bitwarden-desktop
          spotify
          (writeShellApplication {
            name = "disable-lid";
            runtimeInputs = [ systemd ];
            text = ''
              exec systemd-inhibit \
                --what=handle-lid-switch \
                --who="disable-lid" \
                --why="Manual lid-close override" \
                sleep infinity
            '';
          })
        ]
        ++ lib.optionals stdenv.isLinux [
          wl-clipboard
          loupe
          freetube
          signal-desktop
          grim
          slurp
          swappy
          # Communication and media
          thunderbird
          obs-studio
          gimp
          inkscape
          obsidian
        ];
    };
}
