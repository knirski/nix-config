{
  aspects.homeManager.desktop =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables = lib.mkMerge [
          {
            # $BROWSER for CLI tools that do not speak xdg-open. Use the XDG
            # launcher so the managed MIME associations select Firefox.
            # zbook also gets this from environment.sessionVariables on the
            # NixOS side.
            BROWSER = "xdg-open";
          }

          # GTK_THEME=Adwaita:dark forces Electron's native menu bars
          # (rendered via GTK widgets) to use the dark theme, which
          # Adwaita-dark's CSS/theme settings in dconf don't reliably
          # achieve in every display backend (XWayland vs Wayland).
          # Applied globally so every Electron app picks it up without
          # per-app wrapper patches. Harmless on non-Linux/macOS hosts
          # (the env var is simply unused).
          (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
            GTK_THEME = "Adwaita:dark";
          })
        ];

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
            vlc
            spotify
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
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
            eog
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
      # Nautilus is the default file manager on Linux desktop hosts: folders
      # and trash:// URLs resolve to it via xdg-open (Yazi's opener, DMS dock
      # trash, gio). This HM aspect is the single source of truth — imported
      # by zbook, ubuntu, and macbook — so the nautilus package and these
      # defaults follow the desktop aspect wherever it goes. GVfs (trash,
      # automounts) comes from the host's NixOS desktop aspect (zbook) or the
      # stock Ubuntu GNOME base (ubuntu). Darwin (macbook) has no nautilus
      # build: Finder is the default file manager there and `open` resolves
      # folders natively.
      # Firefox on every desktop host, through the module rather than a bare
      # package so profiles and policies can be declared later. It supports
      # darwin (it knows the Library/Application Support layout and the
      # defaults id), but `package` defaults to pkgs.firefox on every
      # platform, and that is not in the binary cache for aarch64-darwin --
      # macbook would compile the browser from source on every bump. Give
      # darwin firefox-bin, which repackages Mozilla's official build.
      #
      # zbook additionally enables NixOS's programs.firefox in
      # modules/nixos/desktop.nix, so it ends up with the browser in both the
      # system and user profile. Same derivation, and the user profile takes
      # precedence on PATH, so this is duplication rather than conflict.
      programs.firefox = {
        enable = true;
        package = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.firefox-bin else pkgs.firefox;
      };

      # Firefox rewrites ~/.config/mimeapps.list itself whenever it decides it
      # should be the default browser, replacing the symlink with a plain
      # file. Home Manager then refuses to activate, because backing the file
      # up would clobber the .backup left by the previous activation. Declare
      # ownership so it is overwritten instead: the whole point of
      # xdg.mimeApps is that this file is generated, and anything Firefox
      # wrote there is exactly what we are overriding.
      # The guard wraps the whole attribute, not the `force` leaf: setting a
      # leaf under mkIf still creates the "mimeapps.list" entry, which on
      # darwin has no source and fails to evaluate.
      xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        "mimeapps.list".force = true;
      };

      xdg.mimeApps = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        # HM writes ~/.config/mimeapps.list only when enable is set
        # (default: false) — without it, defaultApplications is inert.
        enable = true;
        defaultApplications = {
          "inode/directory" = "org.gnome.Nautilus.desktop";
          "x-scheme-handler/trash" = "org.gnome.Nautilus.desktop";

          # Firefox for everything web-facing. zbook also gets these at the
          # system level from modules/nixos/desktop.nix; the user-level file
          # wins where both exist, and both name firefox.desktop, so they
          # agree. Ubuntu has no system-level equivalent, which is why the
          # apt Firefox had claimed the association through a
          # userapp-Firefox-*.desktop of its own making.
          "text/html" = "firefox.desktop";
          "application/xhtml+xml" = "firefox.desktop";
          "x-scheme-handler/http" = "firefox.desktop";
          "x-scheme-handler/https" = "firefox.desktop";
          "x-scheme-handler/about" = "firefox.desktop";
          "x-scheme-handler/unknown" = "firefox.desktop";

          # Desktop login callbacks must return to the application that
          # started the browser flow. Keep these explicit in the user-level
          # database because Firefox may rewrite this file when it claims the
          # ordinary web associations.
          "x-scheme-handler/claude" = "com.anthropic.Claude.desktop";
          "x-scheme-handler/com.cloudflare.warp" = "com.cloudflare.warp.desktop";
        };
      };

      services.gpg-agent = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        pinentry.package = pkgs.pinentry-gnome3;
      };
    };
}
