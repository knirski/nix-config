## Single source of truth for which flake checks are KVM-backed (built via
## lib/testing/run-kvm-test.nix's `runKvmTest` wrapper, and gated by ci.yml's
## `resilience` job checking /dev/kvm before running). Referenced by:
##   - the four check-definition modules that each declare one KVM check
##     (backup-integration-check.nix, dns-dhcp-vm-check.nix,
##     impermanence-vm-check.nix, clipboard-protocol-check.nix), so a rename
##     here forces the matching rename there instead of silently diverging;
##   - modules/parts/kvm-gate-drift-check.nix, which proves ci.yml's
##     `resilience` job and the justfile's `test-resilience` recipe each
##     build exactly this set, with nothing missing or extra on either side.
## Plain data, no module system -- kept outside modules/ so import-tree never
## sees it, mirroring lib/observability/btrfs-metrics.nix.
{
  backupUnitVm = "backup-unit-vm";
  clipboardProtocols = "clipboard-protocols";
  dnsDhcpVm = "dns-dhcp-vm";
  impermanenceVm = "impermanence-vm";
}
