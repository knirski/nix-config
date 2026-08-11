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

      environment.systemPackages = with pkgs; [
        firefox
        simple-scan # scanning GUI
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
