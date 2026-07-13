{
  # NVIDIA Optimus: Intel for desktop, NVIDIA on-demand for games
  lanAppliance.services.nvidia = {
    enable = true;
    prime = {
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
    syncMode = "offload";
  };
}
