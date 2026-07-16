{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      programs = {
        zed-editor.enable = true;
        git.settings.alias.visual = "!gitk";
      };

      # Neovim clipboard integration (requires wl-clipboard on Wayland)
      home.file.".config/nvim/after/plugin/clipboard.lua".text = ''
        vim.opt.clipboard = "unnamedplus"
      '';

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
