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

        printing.enable = true;
        blueman.enable = true;
        gnome.gnome-keyring.enable = true;
      };

      security.rtkit.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        nerd-fonts.jetbrains-mono
        nerd-fonts.fira-code
        nerd-fonts.symbols-only
      ];

      environment.systemPackages = with pkgs; [
        firefox
      ];

      hardware.bluetooth.enable = true;
    };
}
