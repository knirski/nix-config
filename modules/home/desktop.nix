{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      programs = {
        zed-editor.enable = true;
        gh = {
          enable = true;
          extensions = with pkgs; [
            gh-dash
            gh-pr-review
          ];
        };
        git.settings.alias.visual = "!gitk";
      };

      # Neovim clipboard integration (requires wl-clipboard on Wayland)
      home.file.".config/nvim/after/plugin/clipboard.lua".text = ''
        -- Only enable system clipboard on desktop sessions
        if vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY then
          vim.opt.clipboard = "unnamedplus"
        end
      '';

      # Manual lid-close inhibitor.  Run `disable-lid` in a terminal before
      # closing the laptop lid to keep the system awake (useful when moving
      # between rooms while media is playing or a download is running).
      # Cancel it with Ctrl+C — the inhibitor is released on script exit.
      # Linux only — macOS manages lid behavior via pmset.
      home.packages =
        with pkgs;
        (
          [
            antigravity-cli
            mpv
            spotify
          ]
          ++ lib.optionals stdenv.isLinux [
            bitwarden-desktop
          ]
        )
        ++ lib.optionals stdenv.isLinux [
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
