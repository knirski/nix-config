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
    "github"
    "Downloads"
    "Documents"
    "Pictures"
    "Music"
    "Videos"
    ".local/share/Steam"
    ".local/share/lutris"
  ];

  bestEffort = [
    ".local/share/direnv"
    ".cache/DankMaterialShell"
    ".local/share/applications"
    "tmp"
    "Pictures/Screenshots"
  ];

  all = durable ++ bestEffort;
}
