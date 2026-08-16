{
  # Maintenance: enable for this host, set disk to zbook's NVMe
  lanAppliance.services.maintenance = {
    enable = true;
    smartdDevices = [
      "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2N11292JQEJC"
    ];
    # Both fatal NVMe wedges (2026-08-11, 2026-08-14) followed the smartd
    # scheduled short self-test start by ≤13 s, and the controller can't even
    # read back its own self-test log page — tests add risk without signal on
    # this drive. SMART attribute monitoring stays on; only the tests are
    # dropped. Soyo's SATA SSD keeps its schedule (see AGENTS.md).
    smartdSelfTestSchedule = null;
    # zbook alerts go to its own ntfy.sh channel (zbook-alerts-*), so the
    # maintenance aspect reads zbook's host-specific secrets (declared in
    # modules/parts/zbook.nix) rather than soyo's channel secrets.
    ntfyTokenSecret = "zbook-ntfy-token";
    ntfyTopicSecret = "zbook-ntfy-topic";
  };
}
