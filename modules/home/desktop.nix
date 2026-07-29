{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables =
          # GTK_THEME=Adwaita:dark forces Electron's native menu bars
          # (rendered via GTK widgets) to use the dark theme, which
          # Adwaita-dark's CSS/theme settings in dconf don't reliably
          # achieve in every display backend (XWayland vs Wayland).
          # Applied globally so every Electron app picks it up without
          # per-app wrapper patches. Harmless on non-Linux/macOS hosts
          # (the env var is simply unused).
          lib.mkIf pkgs.stdenv.isLinux {
            GTK_THEME = "Adwaita:dark";
          };

        # Neovim clipboard integration (requires wl-clipboard on Wayland)
        file.".config/nvim/after/plugin/clipboard.lua".text = ''
          -- Only enable system clipboard on desktop sessions
          if vim.env.DISPLAY or vim.env.WAYLAND_DISPLAY then
            vim.opt.clipboard = "unnamedplus"
          end
        '';

        packages =
          with pkgs;
          [
            antigravity-cli
            mpv
            spotify
          ]
          ++ lib.optionals stdenv.isLinux [
            bitwarden-desktop
            rbw
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
          ];
      };

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

      # Upgrade base's terminal-safe pinentry to a GUI prompt now that a
      # graphical session is guaranteed. pinentry-gnome3 is a Linux/GTK
      # package with no Darwin build, so guard even though this aspect is
      # also imported on macbook (aerospace/Aqua, not GNOME).
      services.gpg-agent = lib.mkIf pkgs.stdenv.isLinux {
        pinentry.package = pkgs.pinentry-gnome3;
      };
    };
}
