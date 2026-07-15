# Kanshi output profiles for zbook.
#
#   eDP-1  — built-in laptop panel (1920×1200, BOE)
#   DP-6   — Thunderbolt dock DisplayPort to Iiyama PL2792Q (2560×1440)
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
          criteria = "DP-6";
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
