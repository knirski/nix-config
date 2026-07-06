{
  # This module depends on package overrides in the host assembler:
  #   - cosmic-ext-* packages come from the stable nixpkgs input overlay
  #     (not available in nixpkgs-unstable used as the primary channel).
  #   - cosmic-fan-control is a local package under modules/pkgs/.
  # See modules/parts/zbook.nix for the overlay declaration.
  # Future hosts toggling this aspect must replicate that overlay.
  aspects.nixos.desktop =
    { pkgs, ... }:
    {
      services = {
        # COSMIC desktop environment — full DE with built-in tiling
        desktopManager.cosmic.enable = true;
        displayManager.cosmic-greeter.enable = true;

        # Flatpak for apps not in nixpkgs (e.g. fan-control)
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

        printing.enable = true;
        blueman.enable = true;
        gnome.gnome-keyring.enable = true;
      };

      security.rtkit.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        (nerdfonts.override {
          fonts = [
            "JetBrainsMono"
            "FiraCode"
            "NerdFontsSymbolsOnly"
          ];
        })
      ];

      environment.systemPackages = with pkgs; [
        firefox
        cosmic-ext-applet-external-monitor-brightness
        cosmic-ext-tweaks
        cosmic-fan-control
      ];

      hardware.bluetooth.enable = true;
    };
}
