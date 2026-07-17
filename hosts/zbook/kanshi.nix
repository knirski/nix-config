# Kanshi output profiles for zbook.
#
#   eDP-1  — built-in laptop panel (1920×1200, BOE)
#   Iiyama North America PL2792Q — Thunderbolt dock DisplayPort to external (2560×1440)
#
#   The external is matched by EDID description (including serial) rather
#   than connector name so that udev restarts during deploy don't break
#   matching when the Thunderbolt dock re-enumerates.
_: {

  services.kanshi.settings = [
    # Docked: external to the right of the laptop panel.
    {
      profile.name = "docked";
      profile.outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          scale = 1.0;
          position = "0,0";
          mode = "1920x1200@60.003";
        }
        {
          # Match by EDID description (stable across connector renames)
          criteria = "Iiyama North America PL2792Q 1152194804219";
          status = "enable";
          scale = 1.0;
          position = "1920,0";
          mode = "2560x1440@69.923";
        }
      ];
    }
    # Alone: laptop only (undocked).
    {
      profile.name = "alone";
      profile.outputs = [
        {
          criteria = "eDP-1";
          status = "enable";
          scale = 1.0;
          position = "0,0";
          mode = "1920x1200@60.003";
        }
      ];
    }
  ];
}
