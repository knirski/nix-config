{ lib, ... }:
{
  aspects.nixos.laptop = _: {
    services = {
      power-profiles-daemon.enable = true;
      thermald.enable = true;
      upower.enable = true;
      fwupd.enable = true;
    };

    # CPU frequency scaling governor (powersave by default on battery)
    powerManagement.cpuFreqGovernor = "powersave";
    powerManagement.powertop.enable = true;

    # Intel P-State driver (better power management on 12th/13th gen)
    boot.kernelParams = [
      "intel_pstate=active"
      # Disable USB autosuspend for Logitech Unifying (c52b) and Bolt (c532)
      # receivers at the USB core level, before powertop or udev can touch
      # it. The "b" flag prevents the USB core from ever autosuspending the
      # device — immutable, immune to powertop --auto-tune.
      # https://docs.kernel.org/admin-guide/kernel-parameters.html
      "usbcore.quirks=046d:c52b:b,046d:c532:b"
    ];

    # Laptop lid switch handling
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandleLidSwitchExternalPower = "lock";
      HandleLidSwitchDocked = "ignore";
    };

    # udev rules to disable USB/Thunderbolt controller wake — prevents the
    # laptop from immediately resuming after suspend when a USB-C dock
    # (ethernet, monitor, receiver) is connected.
    # Udev rules survive device re-enumeration and resume, unlike a one-shot
    # systemd service that can race with powertop or hotplug events.
    services.udev.extraRules = lib.mkAfter ''
      # USB xHCI controllers (both internal USB and USB4 host)
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="xhci_hcd", ATTR{power/wakeup}="disabled"
      # USB4/Thunderbolt controllers
      ACTION=="add", SUBSYSTEM=="pci", DRIVER=="thunderbolt", ATTR{power/wakeup}="disabled"
      # PCIe root ports for Thunderbolt (TRP0, TRP2) and card reader (RP04)
      # on this Intel Raptor Lake host — identified by device ID.
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0xa76e", ATTR{power/wakeup}="disabled"
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0xa72f", ATTR{power/wakeup}="disabled"
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{device}=="0x51bb", ATTR{power/wakeup}="disabled"

    '';
  };
}
