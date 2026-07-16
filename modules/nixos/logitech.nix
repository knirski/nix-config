# Logitech device configuration aspect.
#
# Enables the Solaar daemon and udev rules for Logitech Unifying/Bolt
# receivers, letting you pair devices, remap buttons, check battery levels,
# and configure device-specific settings from the desktop.
#
# The Solaar GUI (`solaar` command) provides a graphical interface; the
# `solaar-cli` tool works headlessly for scripting.
#
# ## Usage
#
# Enable this aspect in the host assembler:
# ```nix
# aspects.nixos.logitech
# ```
#
# Then launch `solaar` from your desktop or run `solaar-cli --help` for
# the command-line interface.
#
# ## Sources
#
# - Solaar: https://pwr-solaar.github.io/Solaar/
# - nixpkgs: hardware.logitech.wireless
{
  aspects.nixos.logitech = { pkgs, ... }: {
    # Enable udev rules for Logitech wireless receivers (Unifying/Bolt)
    # and start the solaar service (daemon + D-Bus activation).
    hardware.logitech.wireless.enable = true;

    # Solaar provides both the `solaar` GUI and `solaar-cli` tools.
    # The daemon is already enabled via hardware.logitech.wireless above,
    # but we explicitly include the package for the GUI binary.
    environment.systemPackages = with pkgs; [ solaar ];
  };
}
