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
  };
}
