# github
- When replying to GitHub PR review comments, post replies as inline comments on individual review threads rather than as a single summary comment on the PR. Confidence: 0.65
- For taste-only PRs (small changes to `.commandcode/taste/`), use a shorter CI pipeline or skip the full CI pipeline that runs on code changes — such trivial PRs don't need the full build/check suite. Confidence: 0.65
- When waiting for PR checks to pass, use `gh run watch` instead of `sleep` to poll for completion. Confidence: 0.70

# darwin
- For macOS tiling window management on nix-darwin hosts, use Aerospace (not yabai/skhd, Rectangle, or other alternatives) — the user wants max similarity with their Sway setup. Confidence: 0.55

# general
- When adding new cross-platform hosts (macOS, Ubuntu Linux), maximize desktop experience parity with existing NixOS hosts (zbook's Sway+DMS+Kitty+Starship+Zsh setup) to the extent sensible given platform constraints — prefer equivalent tools (Aerospace over Mac native tiling, DMS on all platforms, same shell/terminal/prompt/config) rather than diverging to platform-native defaults. Confidence: 0.65

# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/
See [taste-(continuously-learned-by-[commandcode][cmd])/taste.md](taste-(continuously-learned-by-[commandcode][cmd])/taste.md)

# secrets
- Name the master identity public key file in `secrets/` consistently with the SSH key filename (e.g., `krzysiek.age.pub` → `agenix_master.pub`) to distinguish the master encryption key from the SSH login key (`krzysiek-authorized-key.pub`). Confidence: 0.60

# zed
- For this project: when configuring Zed via Home Manager, keep only `enable` and `extensions` — omit `userSettings` (theme, fonts, auto_update, etc.) because the user uses Zed account sync, which manages those settings server-side and pushes them to all signed-in instances. Confidence: 0.70

# nixos
See [nixos/taste.md](nixos/taste.md)
