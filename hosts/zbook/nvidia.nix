{ lib, ... }:
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

  # Disable NVIDIA runtime power management to prevent the ABBA rw-semaphore
  # deadlock in rm_acpi_nvpcf_notify (the ACPI handler for USB-C dock events).
  # When the GPU is runtime-suspended, Thunderbolt dock hotplug ACPI events
  # can race with the nv_queue internal lock, permanently wedging the GPU.
  # The existing finegrained = false workaround in the nvidia module reduces
  # but doesn't eliminate this — disabling PM entirely avoids the race.
  # Ref: modules/nixos/nvidia.nix lines 47-63
  hardware.nvidia.powerManagement.enable = lib.mkForce false;
}
