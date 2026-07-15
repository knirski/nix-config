# Home Manager aspect: kanshi — automatic output profile switching on hotplug.
#
# This is the generic enabler. Host-specific output layouts (connector
# names, positions, resolutions) belong in a `<host>/kanshi.nix` file
# that sets `services.kanshi.settings`, imported alongside this aspect.
{
  aspects.homeManager.kanshi = _: {
    services.kanshi = {
      enable = true;
      # No default settings — each host must set `services.kanshi.settings`
      # with its own profiles.
      settings = [ ];
    };
  };
}
