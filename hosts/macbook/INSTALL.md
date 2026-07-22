# macbook installation and deployment

The canonical first-install runbook is
[`docs/install-macbook.md`](../../docs/install-macbook.md). Follow it from top
to bottom when provisioning the macbook; it covers Nix installation, host-key
creation, agenix rekeying, first `darwin-rebuild`, and validation.

For routine deployment of an existing installation:

- pull the latest flake inputs: `nix flake update`
- activate: `darwin-rebuild switch --flake .#macbook`
- or: `just deploy macbook`
