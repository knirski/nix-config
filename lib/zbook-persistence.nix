# One inventory feeds both the zbook preservation module and its invariants.
# Keeping the classification beside the paths prevents a new persisted
# directory from silently drifting out of the reviewable durability contract.
rec {
  durable = [
    ".ssh"
    ".agents"
    ".local/share/keyrings"
    ".local/state/home-manager"
    ".local/state/DankMaterialShell"
    ".local/share/dankcalendar"
    ".config"
    ".commandcode"
    ".codex"
    ".claude"
    ".local/state/wireplumber"
    ".local/share/atuin"
    ".local/share/zed"
    # agent-browser keeps its downloaded browser and session state here;
    # retain it across zbook's erase-your-darlings root rollback.
    ".agent-browser"
    "github"
    "Downloads"
    "Documents"
    "Pictures"
    "Music"
    "Videos"
    ".local/share/Steam"
    ".local/share/lutris"
    # win-usb VM state: OVMF NVRAM vars. Must survive the ephemeral root
    # wipe — see docs/win-usb.md. (Disk images are NOT persisted here;
    # they live on the NAS and win-usb-image requires an explicit
    # destination argument.)
    ".local/share/win2go"
  ];

  bestEffort = [
    ".local/share/direnv"
    ".cache/DankMaterialShell"
    ".cache/quickshell"
    ".local/share/applications"
    "tmp"
    "Pictures/Screenshots"
  ];

  all = durable ++ bestEffort;
}
