# flake-parts module: assembles homeConfigurations.ubuntu
# Professional work laptop (Ubuntu 24.04 LTS, standalone Home Manager).
# No NixOS or nix-darwin — only user environment managed by HM.
{ config, inputs, ... }:
let
  # Ubuntu enables aspects.homeManager.desktop below, so it needs the
  # reviewed insecure-package exceptions (see
  # lib/insecure-package-exceptions.nix for what/why).
  insecurePackageExceptions = import ../../lib/insecure-package-exceptions.nix;
in
{
  flake.homeConfigurations.ubuntu = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = import inputs.nixpkgs-unstable (
      (import ../../lib/mk-nixpkgs-args.nix {
        permittedInsecurePackages = map (e: e.package) insecurePackageExceptions;
      })
      // {
        system = "x86_64-linux";
      }
    );
    modules = [
      config.aspects.homeManager.base
      config.aspects.homeManager.development
      config.aspects.homeManager.desktop
      config.aspects.homeManager.ssh
      config.aspects.homeManager.sway
      inputs.dms.homeModules.dank-material-shell
      inputs.dcal.homeModules.dank-calendar
      inputs.dsearch.homeModules.default
      inputs.dms-plugins.homeModules.dms-plugin-registry
      (
        { config, pkgs, ... }:
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

          wallpaper = pkgs.callPackage ../_pkgs/hive-grid-wallpaper.nix { };
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

              # Replacing the snaps of the same name. Both are unfree, which
              # lib/mk-nixpkgs-args.nix already permits. Spotify and Bitwarden
              # need no entry here: aspects.homeManager.desktop provides them.
              pkgs.vscode
              # jetbrains.idea is the Ultimate build; nixpkgs dropped the
              # -ultimate suffix and keeps idea-community as the free one.
              pkgs.jetbrains.idea
            ];
          };

          systemd.user.services = {
            dms.Service.Environment = [ "PATH=${graphicalServicePath}" ];
            dcal.Service.Environment = [ "PATH=${graphicalServicePath}" ];
          };

          # Distinguishes this machine from the other hosts at a glance. Sway
          # renders the background itself, so this needs no extra service, and
          # it leaves DankMaterialShell's settings.json writable -- setting it
          # through the DMS module option would replace that whole file with a
          # read-only store symlink and stop the UI persisting any change.
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
