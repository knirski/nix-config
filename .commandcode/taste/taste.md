# github
See [github/taste.md](github/taste.md)
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

# nix
- `lazyAttrsOf lib.types.raw` accepts function values — a module returning a plain function (not declaring options via `options.aspects.darwin.base = ...`) works when assigned to a `raw`-typed option slot. This is why `modules/darwin/base.nix`'s `_: { aspects.darwin.base = { pkgs, ... }: { ... }; }` evaluates correctly despite not explicitly registering the option namespace. Confidence: 0.70

# cross-platform
- When adding new hosts with different platforms (macOS/darwin, Linux), guard Linux-only packages in shared Home Manager modules behind `lib.optionals stdenv.isLinux [...]` — common offenders: `systemd` as a runtime dependency, x86_64-linux-only binaries (static Go binaries from GitHub releases), Electron apps (bitwarden-desktop, signal-desktop), and platform-specific desktop packages. Include a comment explaining why the guard is needed. Confidence: 0.70
- The canonical Sway+DMS desktop experience is the baseline target for all Linux hosts (including standalone HM on Ubuntu), not just NixOS hosts. Use `aspects.homeManager.sway` on Linux hosts; Aerospace is the macOS-specific alternative only. Confidence: 0.65
