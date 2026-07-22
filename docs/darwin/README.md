# macOS / nix-darwin documentation

This directory covers macbook-specific documentation for the nix-darwin host.

- [`docs/install-macbook.md`](../install-macbook.md) — first install from a
  stock macOS system.
- [`hosts/macbook/INSTALL.md`](../../hosts/macbook/INSTALL.md) — macbook deploy
  pointer.

The macbook uses nix-darwin, which is structurally different from NixOS:

- Home Manager aspects (`modules/home/`) are shared with NixOS hosts (zbook)
  and standalone HM hosts (ubuntu).
- Darwin aspects (`modules/darwin/`) mirror NixOS aspects (`modules/nixos/`)
  but use launchd, not systemd, where a native service wrapper is needed.
- macOS system settings (Dock, Finder, keyboard repeat) are configured in
  `modules/darwin/base.nix` via `system.defaults` — the nix-darwin equivalent
  of NixOS options.

Cross-platform parity goals are documented in
[`docs/workstation-setup.md`](../workstation-setup.md).
