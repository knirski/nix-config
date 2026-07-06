# Taste (Continuously Learned by [CommandCode][cmd])

[cmd]: https://commandcode.ai/

# git
- When SSH push fails due to host key verification, use `gh` authentication via HTTPS by temporarily switching remote URL to `https://github.com/{owner}/{repo}.git`, pushing, then restoring SSH remote. Confidence: 0.70
- Split changes into focused, smaller commits rather than bundling everything into one commit. Confidence: 0.80

# nix
- In multi-host NixOS flakes where hosts use different nixpkgs channels (stable vs unstable), use separate input URLs pinned to matching branches per host rather than a shared single input — applies to home-manager and other channel-sensitive inputs. Confidence: 0.78
- Prefer the short-form flake input URL (e.g., `github:nix-community/home-manager`) over explicitly appending the default branch (`/master`), as the short form is cleaner and resolves to the same default branch. Confidence: 0.60
