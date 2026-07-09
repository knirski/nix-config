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

    # Disable USB wake for the dock's Realtek RTL8153 Ethernet adapter.
    # On s2idle (S0ix), link-state changes from the >1Gbps LAN chip
    # trigger an immediate re-wake after suspend entry, even when the
    # cable is idle. Only the dock LAN is targeted, not internal USB.
    services.udev.extraRules = lib.mkAfter ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="8153", ATTR{power/wakeup}="disabled"
    '';

    # Disable Thunderbolt host controller and DMA wake sources before every
    # suspend. /proc/acpi/wakeup is a toggle — writing a device name
    # switches it on/off — so we only write if currently enabled.
    # On s2idle, the HP Thunderbolt dock (TDM0/TDM1) fires an immediate
    # wake event on suspend entry, overriding the RTL8153 udev fix.
    systemd.services.disable-thunderbolt-wake = {
      description = "Disable Thunderbolt wake sources before suspend";
      before = [ "systemd-suspend.service" ];
      wantedBy = [ "sleep.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        for dev in TXHC TDM0 TDM1; do
          if grep -q "^$dev[[:space:]]\+S[0-9][[:space:]]\+\*enabled" /proc/acpi/wakeup; then
            echo "$dev" > /proc/acpi/wakeup
          fi
        done
      '';
    };
  };
}
