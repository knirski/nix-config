# darwin
- For macOS tiling window management on nix-darwin hosts, use Aerospace (not yabai/skhd, Rectangle, or other alternatives) — the user wants max similarity with their Sway setup. Confidence: 0.55

# general
- When adding new cross-platform hosts (macOS, Ubuntu Linux), maximize desktop experience parity with existing NixOS hosts (zbook's Sway+DMS+Kitty+Starship+Zsh setup) to the extent sensible given platform constraints — prefer equivalent tools (Aerospace over Mac native tiling, DMS on all platforms, same shell/terminal/prompt/config) rather than diverging to platform-native defaults. Confidence: 0.65

# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/
See [taste-(continuously-learned-by-[commandcode][cmd])/taste.md](taste-(continuously-learned-by-[commandcode][cmd])/taste.md)

# secrets
- Name the master identity public key file in `secrets/` consistently with the SSH key filename (e.g., `krzysiek.age.pub` → `agenix_master.pub`) to distinguish the master encryption key from the SSH login key (`krzysiek-authorized-key.pub`). Confidence: 0.60

# nixos
See [nixos/taste.md](nixos/taste.md)
