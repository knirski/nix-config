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
            bitwarden-cli
            rbw
            nautilus # default file manager (see xdg.mimeApps below)
            # rbw spawns `pinentry` directly (not through gpg-agent). The
            # nixpkgs `pinentry` meta-package was removed; provide a thin
            # wrapper that delegates to the GTK3 pinentry we already have.
            (pkgs.writeShellApplication {
              name = "pinentry";
              runtimeInputs = [ pkgs.pinentry-gnome3 ];
              text = ''exec pinentry-gnome3 "$@"'';
            })
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
            gh-stack
          ];
        };
        git.settings.alias.visual = "!gitk";
      };

      # Upgrade base's terminal-safe pinentry to a GUI prompt now that a
      # graphical session is guaranteed. pinentry-gnome3 is a Linux/GTK
      # package with no Darwin build, so guard even though this aspect is
      # also imported on macbook (aerospace/Aqua, not GNOME).
      # Nautilus is THE default file manager on every desktop host (all but
      # the headless soyo): folders and trash:// URLs resolve to it via
      # xdg-open (Yazi's opener, DMS dock trash, gio). This HM aspect is the
      # single source of truth — it is imported by zbook, ubuntu, and macbook
      # — so the nautilus package and these defaults follow the desktop aspect
      # wherever it goes. GVfs (trash, automounts) comes from the host's NixOS
      # desktop aspect (zbook) or the stock Ubuntu GNOME base (ubuntu).
      # Darwin (macbook) has no nautilus build: Finder is the default file
      # manager there and `open` resolves folders natively.
      xdg.mimeApps = lib.mkIf pkgs.stdenv.isLinux {
        defaultApplications = {
          "inode/directory" = "org.gnome.Nautilus.desktop";
          "x-scheme-handler/trash" = "org.gnome.Nautilus.desktop";
        };
      };

      services.gpg-agent = lib.mkIf pkgs.stdenv.isLinux {
        pinentry.package = pkgs.pinentry-gnome3;
      };
    };
}
