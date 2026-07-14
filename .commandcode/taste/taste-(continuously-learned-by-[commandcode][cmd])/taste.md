# Taste (Continuously Learned by [CommandCode][cmd])
- When SSH push fails due to host key verification, use `gh` authentication via HTTPS by temporarily switching remote URL to `https://github.com/{owner}/{repo}.git`, pushing, then restoring SSH remote. Confidence: 0.70
- Split changes into focused, smaller commits rather than bundling everything into one commit. Confidence: 0.80
- Use `gh` (GitHub CLI) for committing and pushing instead of raw `git` push/pull commands. Confidence: 0.72
- In this project, use H2 (`##`) for category headings in markdown files to pass markdownlint (avoids MD025 "Multiple top-level headings"). Confidence: 0.80
- In multi-host NixOS flakes where hosts use different nixpkgs channels (stable vs unstable), use separate input URLs pinned to matching branches per host rather than a shared single input — applies to home-manager and other channel-sensitive inputs. Confidence: 0.78
- Prefer the short-form flake input URL (e.g., `github:nix-community/home-manager`) over explicitly appending the default branch (`/master`), as the short form is cleaner and resolves to the same default branch. Confidence: 0.60

# nixos
- Isolate desktop-environment-specific fixes into their own Nix module file (e.g., `cosmic-fixes.nix`) so swapping to a different DE (Hyprland, Sway) only requires swapping that file. Confidence: 0.80
- When packaging an npm package as a Nix derivation, leave clear inline comments documenting how to update the version (e.g., regenerate lockfile, get new hash). Confidence: 0.70
- Enable `nixpkgs.config.allowUnfree = true` globally for all hosts rather than using per-package allowlists or `NIXPKGS_ALLOW_UNFREE` env var workarounds. Confidence: 0.70

# secrets
- Use agenix-rekey (invariant 5 from AGENTS.md) to manage secrets; never commit plaintext secrets or tokens to the repo. Confidence: 0.80
- Prefer separate per-host secrets (e.g., one Tailscale auth key per host, name secrets like `{host}-{secret}.age`, e.g., `soyo-restic-password.age`, `zbook-restic-password.age`) over sharing a single secret across multiple hosts. Confidence: 0.75
- When referencing a secret source file from the filesystem, use files prefixed with `.dont_commit_` as the convention for sensitive local files that should not be committed. Confidence: 0.70
- Name SSH private key files `{hostname}_ed25519` (e.g., `zbook_ed25519`, `soyo_ed25519`) rather than generic `id_ed25519` to clearly identify which host each key belongs to. Confidence: 0.60

# ci
- Add gitleaks as a pre-commit hook check to prevent committing secrets; it should be part of the pre-commit configuration. Confidence: 0.70
- In a custom `.gitleaks.toml` with only an `[allowlist]` and no `[[rules]]`, set `useDefault = true` to merge the built-in rules with the allowlist; omitting it silently replaces all built-in rules with zero rules, disabling all secret detection. Confidence: 0.72
- When configuring git-hooks.nix hooks, prefer using the framework's built-in predefined hook definitions (e.g., cachix/git-hooks.nix's nixpkgs-fmt, statix, etc.) over custom inline writeShellScriptBin wrappers; predefined hooks are more idiomatic, better maintained, and integrate correctly with pass_filenames and the pre-commit lifecycle. Confidence: 0.60

# general
- When a command output already shows the same state (e.g., "nothing to commit, working tree clean"), do not re-run the command — the initial output is sufficient and redundant re-runs waste time. Confidence: 0.55
- Use zsh as the default shell with starship as the shell prompt theme (switched from spaceship to starship). Confidence: 0.75
- Use oh-my-zsh (or a modern alternative with popular plugins) for zsh plugin management, with the most useful popular plugins enabled. Confidence: 0.70

# git
- Use user name "Krzysztof Nirski" (not "Krzysiek Knirski") when configuring git identity globally. Confidence: 0.80
- Use email "krzysztof.nirski+github@gmail.com" when configuring git identity globally. Confidence: 0.80
- All git operations should use SSH for authentication (not HTTPS or token-based auth). Confidence: 0.80
- Configure git identity (userName, userEmail) globally via Nix/home-manager module, not per-repo in local `.git/config`. Confidence: 0.65
