_: {
  # NVIDIA Optimus: Intel for desktop, NVIDIA on-demand for games
  lanAppliance.services.nvidia = {
    enable = true;
    # The proprietary driver supports disabling GSP, and this ZBook hit an
    # Xid 120 GSP crash while entering s2idle. Keep this host-specific
    # workaround out of the shared NVIDIA aspect.
    # https://wiki.archlinux.org/title/NVIDIA/Troubleshooting#GSP_firmware
    disableGsp = true;
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
    syncMode = "offload";
  };
}
