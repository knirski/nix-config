{
  # This module depends on package overrides in the host assembler:
  #   - cosmic-ext-* packages come from the stable nixpkgs input overlay
  #     (not available in nixpkgs-unstable used as the primary channel).
  # Future hosts toggling this aspect must replicate that overlay.
  aspects.nixos.cosmic =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      services = {
        desktopManager.cosmic.enable = true;
        displayManager.cosmic-greeter.enable = true;
      };

      environment.systemPackages = with pkgs; [
        cosmic-ext-applet-external-monitor-brightness
        cosmic-ext-tweaks
      ];

      # Workaround for https://github.com/pop-os/cosmic-epoch/issues/3012: on dual
      # Intel+NVIDIA PRIME offload, cosmic-comp loses DRM master after suspend and
      # can't recover. Restart the compositor post-resume so it re-acquires DRM
      # master cleanly.
      powerManagement.resumeCommands = lib.mkIf config.workstation.nvidiaConfig.enable ''
        ${pkgs.coreutils}/bin/sleep 2
        PID=$(${pkgs.procps}/bin/pgrep -u krzysiek cosmic-comp)
        if [ -n "$PID" ]; then
          ${pkgs.coreutils}/bin/kill "$PID"
          ${pkgs.coreutils}/bin/sleep 1
        fi
      '';
    };
}
