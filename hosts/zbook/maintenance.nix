{
  # Maintenance: enable for this host, set disk to zbook's NVMe
  lanAppliance.services.maintenance = {
    enable = true;
    smartdDevices = [
      "/dev/disk/by-id/nvme-XPG_GAMMIX_S70_BLADE_2N11292JQEJC"
    ];
  };
}
