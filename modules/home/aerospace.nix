# AeroSpace tiling WM — the macOS analog of Sway.
# Uses HM's built-in programs.aerospace module with TOML config and
# launchd integration. Keybindings mirror the Sway aspect where possible
# (vim-style focus/swap, workspace switching).
#
# Modifier: `cmd` (⌘) — maps to the same physical key as Mod4/Super on
# external keyboards, giving the closest experience to Sway on zbook.
{
  aspects.homeManager.aerospace = _: {
    programs.aerospace = {
      enable = true;
      launchd.enable = true;
      settings = {
        gaps = {
          outer = {
            left = 8;
            bottom = 8;
            top = 8;
            right = 8;
          };
          inner.horizontal = 8;
          inner.vertical = 8;
        };

        mode.main.binding = {
          # Focus (vim-style, matching Sway)
          cmd-h = "focus left";
          cmd-j = "focus down";
          cmd-k = "focus up";
          cmd-l = "focus right";

          # Move
          cmd-shift-h = "move left";
          cmd-shift-j = "move down";
          cmd-shift-k = "move up";
          cmd-shift-l = "move right";

          # Workspaces 1-9
          cmd-1 = "workspace 1";
          cmd-2 = "workspace 2";
          cmd-3 = "workspace 3";
          cmd-4 = "workspace 4";
          cmd-5 = "workspace 5";
          cmd-6 = "workspace 6";
          cmd-7 = "workspace 7";
          cmd-8 = "workspace 8";
          cmd-9 = "workspace 9";

          # Move window to workspace
          cmd-shift-1 = "move-node-to-workspace 1";
          cmd-shift-2 = "move-node-to-workspace 2";
          cmd-shift-3 = "move-node-to-workspace 3";
          cmd-shift-4 = "move-node-to-workspace 4";
          cmd-shift-5 = "move-node-to-workspace 5";
          cmd-shift-6 = "move-node-to-workspace 6";
          cmd-shift-7 = "move-node-to-workspace 7";
          cmd-shift-8 = "move-node-to-workspace 8";
          cmd-shift-9 = "move-node-to-workspace 9";

          # Layout
          cmd-f = "fullscreen";
          cmd-shift-space = "layout floating tiling";

          # Terminal
          cmd-Return = "exec-and-forget kitty";
        };
      };
    };
  };
}
