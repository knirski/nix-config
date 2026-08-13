{
  aspects.nixos.desktop =
    { pkgs, ... }:
    {
      services = {
        # Flatpak for apps not in nixpkgs
        flatpak.enable = true;

        # Audio: PipeWire with WirePlumber
        pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
          wireplumber.enable = true;
          jack.enable = true;
        };

        printing = {
          enable = true;
          drivers = [ pkgs.hplipWithPlugin ];
        };
        blueman.enable = true;
        gnome.gnome-keyring.enable = true;

        # GVfs: userspace virtual filesystem providing mounts, trash:// URIs,
        # and MTP device access. Required by the Nautilus file manager (HM
        # desktop aspect) and DMS's dock trash (`xdg-open trash:///`). Pulls
        # in udisks2 + libmtp udev rules; the default nixpkgs build also
        # compiles the SMB/NFS backends (smb:// and nfs:// in Nautilus).
        # (udisks2 is additionally enabled by fwupd via laptop.nix.)
        gvfs.enable = true;
      };

      security.rtkit.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        nerd-fonts.symbols-only
        inter
      ];

      # ---- Firefox: install + default browser ----

      # `programs.firefox` (rather than a bare `firefox` in systemPackages)
      # is the idiomatic NixOS hook: the package stays in the closure, and
      # the `policies` and `nativeMessagingHosts` options become available
      # declaratively when we need them (e.g. Bitwarden desktop <-> browser
      # extension bridge).
      programs.firefox.enable = true;

      # System-wide default-browser associations (`/etc/xdg/mimeapps.list`).
      # The per-user mimeapps.list written by the HM desktop aspect only
      # overrides inode/directory and trash://; every other type falls
      # through to this file, so http(s) and text/html resolve to Firefox
      # for xdg-open, gio, and apps that open links (Thunderbird, ...).
      # Kept as the system-level fallback for anything reading
      # /etc/xdg/mimeapps.list. The shared HM desktop aspect now sets the same
      # associations per user on every host, and the user file wins where both
      # exist; both name firefox.desktop, so they agree.
      xdg.mime.defaultApplications = {
        "text/html" = "firefox.desktop";
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
      };

      # $BROWSER fallback for CLI tools that don't speak xdg-open.
      environment.sessionVariables.BROWSER = "firefox";

      environment.systemPackages = with pkgs; [
        simple-scan # scanning GUI
        # Bootable USB creator (ISO/WIM/IMG -> one stick, no reformatting).
        # GUI + full filesystem support (ext4/xfs/ntfs/cryptsetup for
        # persistent images). nixpkgs flags its binary blobs as
        # knownVulnerabilities, so the reviewed exception lives in
        # lib/insecure-package-exceptions.nix — keep that entry in sync with
        # any version bump here.
        ventoy-full-gtk
      ];

      hardware = {
        bluetooth.enable = true;
        printers = {
          ensureDefaultPrinter = "HP-LaserJet-Pro-M125nw";
          ensurePrinters = [
            {
              name = "HP-LaserJet-Pro-M125nw";
              location = "Home";
              deviceUri = "socket://10.0.0.11";
              model = "drv:///hp/hpcups.drv/hp-laserjet_pro_mfp_m125nw.ppd";
            }
          ];
        };
        sane = {
          enable = true;
          extraBackends = [ pkgs.hplipWithPlugin ];
        };
      };
    };
}
