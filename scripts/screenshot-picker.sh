#!/usr/bin/env bash
# Screenshot picker — shows a fuzzel menu with capture options.
# macOS: Shift+Cmd+3 (full screen), Shift+Cmd+4 (area)
# Linux: PrtSc → this menu, Shift+PrtSc → direct area capture.

choice=$(
  printf '%s\n' \
    "Full Screen (All Monitors)" \
    "Current Monitor" \
    "Selection Area" |
    fuzzel --dmenu --prompt "Screenshot: " --lines 3
)

dir="$HOME/Pictures/Screenshots"
mkdir -p "$dir"
path="$dir/screenshot-$(date +%Y%m%d-%H%M%S).png"

case "$choice" in
    "Full Screen (All Monitors)")
        grimblast save screen "$path"
        ;;
    "Current Monitor")
        grimblast save output "$path"
        ;;
    "Selection Area")
        grimblast save area "$path"
        ;;
esac
