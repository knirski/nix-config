# flake-parts module: assembles homeConfigurations.ubuntu
# Professional work laptop (Ubuntu 24.04 LTS, standalone Home Manager).
# No NixOS or nix-darwin — only user environment managed by HM.
{ config, inputs, ... }:
let
  # Ubuntu enables aspects.homeManager.desktop below, so it needs the
  # reviewed insecure-package exceptions (see
  # lib/insecure-package-exceptions.nix for what/why).
  insecurePackageExceptions = import ../../lib/insecure-package-exceptions.nix;

  # Bake the keyring backend into the Chromium-family apps rather than relying
  # on desktop detection. Chromium picks its safeStorage backend by sniffing
  # the environment, and under Sway it falls back to basic_text -- plaintext.
  # Exporting a GNOME hint works, but only reaches processes that inherit it:
  # the session script covers Sway's children and
  # systemd.user.sessionVariables covers systemd's, and Signal still broke
  # once from a launcher-spawned transient scope in between. The command-line
  # switch is not environmental, so it holds on every launch path.
  #
  # Ubuntu-scoped: these packages are shared with zbook and macbook, which are
  # not verified against this.
  chromiumSecretStoreOverlay =
    final: prev:
    let
      inherit (final) lib;
      withLibsecret =
        name: exes:
        let
          pkg = prev.${name};
        in
        final.symlinkJoin {
          pname = pkg.pname or (lib.getName pkg);
          version = pkg.version or "";
          name = "${pkg.pname or (lib.getName pkg)}-${pkg.version or "0"}";
          inherit (pkg) meta;
          paths = [ pkg ];
          nativeBuildInputs = [ final.makeWrapper ];
          postBuild = lib.concatMapStrings (exe: ''
            if [ -e "$out/bin/${exe}" ]; then
              rm "$out/bin/${exe}"
              makeWrapper "${pkg}/bin/${exe}" "$out/bin/${exe}" \
                --add-flags "--password-store=gnome-libsecret"
            fi
          '') exes;
        };
    in
    {
      signal-desktop = withLibsecret "signal-desktop" [ "signal-desktop" ];
      slack = withLibsecret "slack" [ "slack" ];
      vscode = withLibsecret "vscode" [ "code" ];
      bitwarden-desktop = withLibsecret "bitwarden-desktop" [ "bitwarden" ];
      google-chrome = withLibsecret "google-chrome" [ "google-chrome-stable" ];
    };

  nixpkgsArgs =
    let
      args = import ../../lib/mk-nixpkgs-args.nix {
        permittedInsecurePackages = map (e: e.package) insecurePackageExceptions;
      };
    in
    args
    // {
      config = args.config // {
        # Android Studio's separate SDK is installed by the shared
        # development aspect on this Linux workstation.
        android_sdk.accept_license = true;
      };
    };
in
{
  flake.homeConfigurations.ubuntu = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs-unstable (
      nixpkgsArgs
      // {
        system = "x86_64-linux";
        overlays = nixpkgsArgs.overlays ++ [ chromiumSecretStoreOverlay ];
      }
    );
    modules = [
      config.aspects.homeManager.base
      config.aspects.homeManager.development
      config.aspects.homeManager.desktop
      config.aspects.homeManager.ssh
      config.aspects.homeManager.sway
      config.aspects.homeManager.deskSwitch
      inputs.dms.homeModules.dank-material-shell
      inputs.dcal.homeModules.dank-calendar
      inputs.dsearch.homeModules.default
      inputs.dms-plugins.homeModules.dms-plugin-registry
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          # GDM starts user services without the interactive shell PATH, and
          # standalone Home Manager has no NixOS profile paths to inherit.
          # DMS and Dank Calendar launch QuickShell as `qs`, so hand their
          # units the Home Manager profile explicitly.  NixOS hosts must not
          # get this — see the note in modules/home/sway.nix.
          graphicalServicePath = builtins.concatStringsSep ":" [
            "${config.home.profileDirectory}/bin"
            "${config.home.homeDirectory}/.local/bin"
            "/usr/local/sbin"
            "/usr/local/bin"
            "/usr/sbin"
            "/usr/bin"
            "/sbin"
            "/bin"
          ];

          # The units are started by systemd, not spawned by Sway, so they do
          # not inherit what the session script exports. DankSearch's launcher
          # runs inside the shell and needs the profile's .desktop files.
          graphicalServiceEnvironment = [
            "PATH=${graphicalServicePath}"
            "XDG_DATA_DIRS=${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/usr/local/share:/usr/share:/var/lib/snapd/desktop"
          ];

          wallpaper = pkgs.callPackage ../_pkgs/hive-grid-wallpaper.nix { };

          # git signs by shelling out to ssh-keygen, which talks to whatever
          # SSH_AUTH_SOCK names. That is the gcr agent here, and gnome-keyring
          # does not implement the signing operation -- it answers
          # "agent refused operation" even though it holds the key. gpg-agent's
          # ssh emulation does implement it, and also has the signing key.
          #
          # So point only the signing path at gpg-agent and leave
          # authentication on gcr, which holds all five keys and is unlocked by
          # the same PAM as the login keyring. Overriding the variable per
          # invocation keeps that split from leaking into anything else.
          gitSshSign = pkgs.writeShellApplication {
            name = "git-ssh-sign";
            runtimeInputs = [ pkgs.openssh ];
            text = ''
              export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gnupg/S.gpg-agent.ssh"
              exec ssh-keygen "$@"
            '';
          };
        in
        {
          home = {
            username = "knirski";
            homeDirectory = "/home/knirski";
            stateVersion = "26.11";

            # GL for every Nix process on this machine, whatever launched it.
            #
            # Nixpkgs patches libglvnd to search
            # /run/opengl-driver/share/glvnd/egl_vendor.d before /etc/glvnd and
            # /usr/share/glvnd.  Ubuntu's own libglvnd has no such path, so a
            # /run/opengl-driver symlink pointing into this profile gives every
            # Nix binary a working EGL vendor while leaving Ubuntu binaries
            # untouched.  mesa's vendor JSON carries an absolute library_path
            # and its RUNPATH resolves its own dependencies, so nothing needs
            # LD_LIBRARY_PATH -- which is what made the alternative (nixGL
            # wrappers) leak Nix libraries into Ubuntu helper processes.
            #
            # This replaces per-launch-path patching.  Wrapping only the
            # compositor covered Sway's children but not `systemd --user`
            # units or D-Bus-activated services, so dms, dcal and Ghostty each
            # needed their own fix; the symlink covers all of them at once.
            #
            # Requires one system-level file, since /run is a tmpfs -- see
            # docs/ubuntu-adaptations.md.  It points at the profile rather than
            # a store path so it is a GC root and follows each generation.
            packages = [
              pkgs.mesa
              pkgs.aegis-rs

              # The official Ubuntu package is intentionally retained, but
              # its Electron binary must be told which Secret Service backend
              # to use.  Under Sway/DMS autodetection falls back to
              # basic_text, so Claude cannot persist the OAuth token and
              # repeatedly asks for elevated reauthentication.
              (pkgs.writeShellApplication {
                name = "claude-desktop";
                text = ''
                  exec /usr/bin/claude-desktop \
                    --password-store=gnome-libsecret "$@"
                '';
              })

              # Slack from nixpkgs rather than the snap. The snap's GPU stack
              # is broken inside its sandbox -- it carries no gpu-2404 content
              # plug, takes the classic opengl interface, and
              # /var/lib/snapd/lib/gl is empty, so mesa cannot find
              # dri_gbm.so and ANGLE fails with "Failed to get system egl
              # display".  Under X11 Chromium fell back; on Wayland it cannot,
              # so the process runs fully (network, tray, API) but never maps
              # a window.  Nothing outside the sandbox can fix that, and
              # --disable-gpu only buys a software-rendered window.  The
              # nixpkgs build is the same upstream version and picks up
              # /run/opengl-driver like every other Nix program here.
              #
              # Work-laptop specific, so it stays out of the shared desktop
              # aspect that zbook and macbook also import.
              pkgs.slack

              # Replacing the apt google-chrome-stable. google-chrome rather
              # than chromium so the existing ~/.config/google-chrome profile
              # carries over -- chromium reads ~/.config/chromium and would
              # present as a fresh browser. Firefox is the default browser
              # (see the shared desktop aspect); this is the second one.
              pkgs.google-chrome
            ];
          };

          systemd.user.services = {
            dms.Service.Environment = graphicalServiceEnvironment;
            dcal.Service.Environment = graphicalServiceEnvironment;
          };

          # Cloudflare's vendor-installed warp-taskbar.service is started by
          # the systemd user manager rather than by Sway.  Its Re-authenticate
          # action uses $BROWSER to hand the Access refresh URL to a browser;
          # standalone Home Manager's `home.sessionVariables` reach shell
          # sessions but not this service.  Export the managed launcher and
          # profile paths to the user manager so WARP follows the Firefox MIME
          # association.  Without XDG_DATA_DIRS, xdg-open cannot resolve the
          # profile's firefox.desktop and falls back to a stale Chrome handler.
          systemd.user.sessionVariables = {
            BROWSER = "xdg-open";
            PATH = graphicalServicePath;
            XDG_DATA_DIRS = "${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:/usr/local/share:/usr/share:/var/lib/snapd/desktop";
          };

          # This user-created launcher was claiming HTTP(S) and was ranked
          # ahead of Firefox by GTK/GIO.  WARP uses that API directly, so its
          # re-authentication flow ignored the explicit mimeapps.list default
          # and repeatedly tried the stale launcher.  Keep Chrome available,
          # but make Firefox the only browser claiming web URLs.
          xdg.desktopEntries.chrome-nvidia = {
            name = "Chrome (NVIDIA GPU)";
            exec = "env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia LIBVA_DRIVER_NAME=nvidia NVD_BACKEND=direct ${pkgs.google-chrome}/bin/google-chrome --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiOnNvidiaGPUs,CanvasOopRasterization --disable-features=UseChromeOSDirectVideoDecoder --gpu-no-context-lost --ozone-platform-hint=auto %U";
            icon = "chromium";
            categories = [
              "Network"
              "WebBrowser"
            ];
            mimeType = [ ];
            settings.StartupWMClass = "google-chrome";
          };

          # The old unmanaged copy in ~/.local/share/applications shadows the
          # profile entry above, so explicitly replace that file as well.
          home.file.".local/share/applications/chrome-nvidia.desktop" = {
            force = true;
            source = "${
              pkgs.makeDesktopItem {
                name = "chrome-nvidia";
                desktopName = "Chrome (NVIDIA GPU)";
                exec = "env __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia LIBVA_DRIVER_NAME=nvidia NVD_BACKEND=direct ${pkgs.google-chrome}/bin/google-chrome --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiOnNvidiaGPUs,CanvasOopRasterization --disable-features=UseChromeOSDirectVideoDecoder --gpu-no-context-lost --ozone-platform-hint=auto %U";
                icon = "chromium";
                categories = [
                  "Network"
                  "WebBrowser"
                ];
              }
            }/share/applications/chrome-nvidia.desktop";
          };

          # WARP is launched by a vendor systemd service whose PATH does not
          # include the Nix profile.  Give the plain Firefox handler an
          # absolute binary path so the browser handoff works without any
          # NVIDIA-specific wrapper.
          home.file.".local/share/applications/firefox.desktop" = {
            force = true;
            source = "${
              pkgs.makeDesktopItem {
                name = "firefox";
                desktopName = "Firefox";
                exec = "${pkgs.firefox}/bin/firefox --name firefox %U";
                icon = "firefox";
                categories = [
                  "Network"
                  "WebBrowser"
                ];
                startupNotify = true;
                mimeTypes = [
                  "text/html"
                  "text/xml"
                  "application/xhtml+xml"
                  "application/vnd.mozilla.xul+xml"
                  "x-scheme-handler/http"
                  "x-scheme-handler/https"
                ];
                extraConfig.StartupWMClass = "firefox";
              }
            }/share/applications/firefox.desktop";
          };

          # The unmanaged cache kept advertising the old MIME claims after
          # the desktop entry was replaced.  Rebuild it from the current
          # entries so GTK/GIO stops recommending Chrome for web URLs.
          home.activation.refreshLocalDesktopDatabase = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            rm -f "$HOME/.local/share/applications/firefox-nvidia.desktop"
            rm -f "$HOME/.local/share/applications/mimeinfo.cache"
            ${pkgs.desktop-file-utils}/bin/update-desktop-database \
              "$HOME/.local/share/applications"
          '';

          # Hand locking to Ubuntu's swaylock. DankMaterialShell's own lock
          # screen cannot authenticate here: it is built against Nix's PAM, so
          # pam_unix looks for unix_chkpwd in the Nix store, where nothing can
          # be setgid shadow, and every unlock attempt fails with
          # "pam_unix(dankshell:auth): authentication failure" no matter what
          # is typed. There is no /etc/pam.d/dankshell either, so PAM falls
          # through to Ubuntu's deny-by-default `other`. Pointing a pam.d file
          # at Ubuntu's modules cannot work around it, because Nix's PAM has
          # neither libselinux nor libcrypt in its closure to dlopen them
          # with.
          #
          # swaylock is an Ubuntu binary with its own PAM stack and the
          # setgid helper, and its package ships /etc/pam.d/swaylock. Setting
          # customPowerActionLock makes DMS delegate every lock path to it --
          # idle timeout, the Ctrl+Mod+l binding and logind lock alike -- and
          # never engage its own WlSessionLock (see Lock.qml `lock()`).
          #
          # NixOS hosts keep the built-in lock: there the PAM service and the
          # setuid wrappers exist, so this stays out of the shared aspect.
          #
          # Pinned into the shell's own settings.json rather than declared
          # through its module option: that option writes the whole file as a
          # read-only store symlink, which would stop the shell persisting
          # anything from its UI. The shared aspect seeds the file; this
          # merges the one key that must not drift.
          home.activation.pinSwaylockAsShellLocker =
            lib.hm.dag.entryAfter [ "unmanageDankMaterialShellSettings" ]
              ''
                target="''${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/settings.json"
                if [ -f "$target" ]; then
                  tmp=$(mktemp)
                  if ${pkgs.jq}/bin/jq --arg v "/usr/bin/swaylock -f -c 14181C" \
                       '.customPowerActionLock = $v' "$target" >"$tmp"; then
                    run install -m 0644 "$tmp" "$target"
                  fi
                  rm -f "$tmp"
                fi
              '';

          # See gitSshSign above: signing goes to gpg-agent, auth stays on gcr.
          programs.git.settings.gpg.ssh.program = lib.getExe gitSshSign;

          # Distinguishes this machine from the other hosts at a glance.
          #
          # Published at a stable path rather than referenced by store path.
          # DankMaterialShell records the desktop wallpaper in session.json,
          # which is mutable runtime state it writes itself (notepad tabs and
          # the like live there too), so that value cannot be generated from
          # Nix without freezing the whole file. Pointing it at this symlink
          # instead keeps the recorded path valid across rebuilds, and the
          # profile keeps the image from being garbage collected.
          #
          # Set it once with:
          #   dms ipc wallpaper set ~/.local/share/wallpapers/hive-grid.png
          #
          # Sway's own background is still set. It is what shows before
          # DankMaterialShell is up, or at all if the shell is not running;
          # when it is, its background layer covers swaybg, since that layer
          # is always an opaque colour and offers no transparent mode.
          #
          # Sway takes the store path directly. It must: home-manager
          # validates the generated config with `sway --validate` inside the
          # build sandbox, where the home directory does not exist, so a path
          # under ~ fails the check. Only the shell needs the stable symlink,
          # because only the shell writes the path into mutable state.
          home.file.".local/share/wallpapers/hive-grid.png".source = wallpaper;

          wayland.windowManager.sway.config.output."*".bg = "${wallpaper} fill";

          # Ubuntu ships no portal backend that serves
          # org.freedesktop.impl.portal.Settings to a Sway session:
          # wlr.portal is UseIn=…;sway;… but only implements Screenshot and
          # ScreenCast, while gtk.portal and gnome.portal implement Settings
          # and are UseIn=gnome.  xdg-desktop-portal then answers every
          # Settings read with "Failed to ReadAll() from Settings
          # implementation: Timeout was reached", and GTK4/libadwaita clients
          # block on that during startup -- Ghostty hangs and exits before it
          # ever maps a window, while non-GTK terminals such as foot are
          # unaffected.  Name the backends explicitly instead: gtk for
          # everything, wlr for the two interfaces it actually provides.
          # NixOS hosts wire portals up in modules/nixos/sway.nix, so this is
          # Ubuntu-only.
          xdg.configFile."xdg-desktop-portal/sway-portals.conf".text = ''
            [preferred]
            default=gtk
            org.freedesktop.impl.portal.Screenshot=wlr
            org.freedesktop.impl.portal.ScreenCast=wlr
          '';

          # GDM starts standalone Home Manager sessions without the NixOS
          # sessionVariables from modules/nixos/sway.nix, so set the wlroots
          # and toolkit variables before Sway starts.  GL needs nothing here:
          # the /run/opengl-driver symlink covers Sway and every client.
          home.file.".local/bin/sway-ubuntu-session" = {
            executable = true;
            text = ''
              #!${pkgs.bash}/bin/bash

              # GDM execs this script directly, so no login shell ever sources
              # ~/.profile or hm-session-vars.sh and the inherited PATH is
              # Ubuntu's system default.  Sway runs keybindings through
              # `sh -c`, which would then fail with "ghostty: not found" for
              # every Home Manager program.  Put the profile on PATH first.
              export PATH="${config.home.profileDirectory}/bin:/nix/var/nix/profiles/default/bin:$PATH"

              # Same reason as PATH: without a login shell nothing puts the
              # profile on XDG_DATA_DIRS, so the session inherits Ubuntu's
              # (/usr/local/share, /usr/share, /var/lib/snapd/desktop) and
              # every .desktop file Home Manager installs is invisible -- the
              # launcher cannot find them and mime defaults naming, say,
              # firefox.desktop resolve to Ubuntu's copy instead of the Nix
              # one. The profile goes first so Nix entries win.
              export XDG_DATA_DIRS="${config.home.profileDirectory}/share:/nix/var/nix/profiles/default/share:''${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}"

              # Pick the SSH agent explicitly. Two run here: Ubuntu's
              # gcr-ssh-agent (socket-activated on $XDG_RUNTIME_DIR/gcr/ssh,
              # unlocked by the same PAM that unlocks the login keyring, and
              # holding every key) and gpg-agent's ssh emulation. Which one
              # won was previously an accident -- SSH_AUTH_SOCK was inherited
              # from the `systemd --user` environment, where it had been left
              # by an earlier X11 session via /etc/X11/Xsession.d/90gpg-agent,
              # a script a Wayland session never runs. That pointed at
              # gpg-agent, which held only some of the keys.
              #
              # gcr is the deliberate choice: gpg-agent keeps GPG, and
              # services.gpg-agent sets no enableSshSupport, so nothing in
              # this repository wants it serving ssh.
              export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"

              export NIXOS_OZONE_WL=1
              export MOZ_ENABLE_WAYLAND=1
              export QT_QPA_PLATFORM='wayland;xcb'
              export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
              export XDG_SESSION_TYPE=wayland

              export XDG_CURRENT_DESKTOP=sway

              export XCURSOR_THEME=Adwaita
              export XCURSOR_SIZE=24

              # SWAY_UNSUPPORTED_GPU and WLR_NO_HARDWARE_CURSORS are
              # deliberately absent. Both are NVIDIA-proprietary workarounds
              # inherited from the NixOS Sway aspect, and this laptop drives
              # every connector from the Intel iGPU. Sway needs no override to
              # accept i915, and forcing software cursors made each pointer
              # movement dirty the whole output and issue a full atomic commit
              # instead of a cursor-plane update -- which the 2560x1440
              # external could not retire before the next one arrived, giving
              # bursts of "Atomic commit failed: Device or resource busy".
              # This laptop's internal panel is driven by Intel.  Keep wlroots
              # from probing the discrete GPU, which has no display outputs
              # and is unused after removing Ubuntu's NVIDIA userspace
              # packages.
              #
              # /dev/dri/cardN indices follow driver probe order and are not
              # stable across kernel upgrades, so identify the GPU by PCI
              # path.  WLR_DRM_DEVICES is colon-separated and the by-path name
              # embeds the PCI address (0000:00:02.0), so it cannot be passed
              # verbatim -- wlroots would split it into three bogus paths and
              # fail with "Found 0 GPUs".  Resolve the symlink to its cardN
              # target instead, and leave the variable unset if the node is
              # missing so Sway falls back to auto-discovery rather than
              # exiting.
              igpu=$(readlink -f /dev/dri/by-path/pci-0000:00:02.0-card 2>/dev/null || true)
              if [ -n "$igpu" ] && [ -e "$igpu" ]; then
                export WLR_DRM_DEVICES="$igpu"
              fi
              unset igpu

              # GDM already runs this script inside a session that has a D-Bus
              # session bus: Ubuntu's dbus-user-session package puts it on
              # $XDG_RUNTIME_DIR/bus, which is also where `systemd --user`
              # listens.  Wrapping the compositor in dbus-run-session would
              # discard that bus for a private one, with two consequences.
              # Sway's `dbus-update-activation-environment --systemd` would
              # talk to the private bus and never reach the real user manager,
              # so its XDG_SESSION_TYPE would stay stale and the dms/dcal
              # ConditionEnvironment gates would keep skipping; and the split
              # would stop notifications, MPRIS and tray items from crossing
              # between Sway's clients and the user services.
              #
              # Probe the socket rather than DBUS_SESSION_BUS_ADDRESS: Ubuntu
              # exports that variable from /etc/X11/Xsession.d, so a bare
              # virtual-console login can have a live bus with the variable
              # unset.  Trusting the variable there would start a private bus
              # and reproduce exactly the failure described above.
              if [ -S "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
                export DBUS_SESSION_BUS_ADDRESS="unix:path=''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus"
                exec "$HOME/.nix-profile/bin/sway" "$@"
              fi
              exec ${pkgs.dbus}/bin/dbus-run-session -- \
                "$HOME/.nix-profile/bin/sway" "$@"
            '';
          };
        }
      )
    ];
  };
}
