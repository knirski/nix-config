# Home Manager aspect: kanshi — automatic output profile switching on hotplug.
#
# Replaces hardcoded `output` directives in sway's extraConfig so the
# display layout adapts when the external monitor is disconnected (laptop
# only) or reconnected (docked).  kanshi watches for udev hotplug events
# and applies the first profile whose criteria match current outputs.
#
# Connector names are hardware-specific:
#   eDP-1  — built-in laptop panel (1920×1200, BOE)
#   DP-6   — Thunderbolt dock DisplayPort to Iiyama PL2792Q (2560×1440)
{
  aspects.homeManager.kanshi = _: {
    services.kanshi = {
      enable = true;
      settings = [
        # Docked: external to the right of the laptop panel.
        {
          profile.name = "docked";
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              scale = 1.0;
              position = "0,0";
              mode = "1920x1200@60";
            }
            {
              criteria = "DP-6";
              status = "enable";
              scale = 1.0;
              position = "1920,0";
              mode = "2560x1440@69.923";
            }
          ];
        }
        # Alone: laptop only (external disconnected or undocked).
        {
          profile.name = "alone";
          profile.outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              scale = 1.0;
              position = "0,0";
              mode = "1920x1200@60";
            }
          ];
        }
      ];
    };
  };
}
