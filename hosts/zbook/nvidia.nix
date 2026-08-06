_: {
  # NVIDIA Optimus: Intel for desktop, NVIDIA on-demand for games
  lanAppliance.services.nvidia = {
    enable = true;
    # The proprietary driver supports disabling GSP, and this ZBook hit an
    # Xid 120 GSP crash while entering s2idle. Keep this host-specific
    # workaround out of the shared NVIDIA aspect.
    # https://wiki.archlinux.org/title/NVIDIA/Troubleshooting#GSP_firmware
    disableGsp = true;
    # This ZBook hit the rm_acpi_nvpcf_notify ABBA rw-semaphore deadlock
    # (permanent GPU wedge, cold reboot required) repeatedly on both 595.x
    # and 610.x.  The nixpkgs-level powerManagement.finegrained = false does
    # NOT disable fine-grained power management — nixpkgs only emits
    # NVreg_DynamicPowerManagement when finegrained = true, and the driver
    # default (0x03) applies otherwise.  This option renders the explicit
    # 0x01 (dynamic PM, no fine-grained gating) that actually prevents the
    # deadlock.  See modules/nixos/nvidia.nix.
    disableFineGrainedPm = true;
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
    syncMode = "offload";
  };
}
