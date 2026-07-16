# Evaluation tests for the boundaries between the appliance, workstation, and
# role-neutral base aspects. These assertions intentionally use NixOS options:
# package lists and generated systemd unit names are incidental implementation
# details, while enabled features are the contract host assemblers must keep.
{ config, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;
      soyo = inputs.self.nixosConfigurations.soyo.config;
      zbook = inputs.self.nixosConfigurations.zbook.config;

      # Evaluating base in isolation proves that shared defaults do not choose
      # a network backend, swap policy, or graphical environment. The fixture
      # also imports home.base through Home Manager: HM modules cannot define
      # NixOS networking or swap options themselves, but evaluating both bases
      # together proves the complete shared baseline remains role-neutral.
      baseOnly =
        (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            config.aspects.nixos.base
            inputs.home-manager.nixosModules.home-manager
            {
              nixpkgs.hostPlatform = "x86_64-linux";
              system.stateVersion = "26.05";
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.fixture = {
                  imports = [ config.aspects.homeManager.base ];
                  home.stateVersion = "26.05";
                };
              };
            }
          ];
        }).config;
      homeBaseOnly = baseOnly.home-manager.users.fixture;

      roleMarker = host: host.environment.etc."nix-config/role".text or null;
      optionEnabled = path: host: lib.attrByPath path false host;
      graphicalFeaturesDisabled =
        host: !host.services.xserver.enable && !host.services.greetd.enable && !host.programs.sway.enable;

      testResults = {
        zbook-no-critical-appliance-services =
          !zbook.services.blocky.enable
          && !zbook.services.dnsmasq.enable
          && !(optionEnabled [ "lanAppliance" "services" "dhcp" "enable" ] zbook);
        zbook-no-remote-unlock =
          !(optionEnabled [ "lanAppliance" "services" "remoteUnlock" "enable" ] zbook)
          && !zbook.boot.initrd.network.ssh.enable;
        zbook-no-server-networking =
          zbook.networking.networkmanager.enable
          && !zbook.networking.useNetworkd
          && !zbook.systemd.network.enable;
        zbook-workstation-role =
          roleMarker zbook == "workstation\n" && zbook.programs.sway.enable && zbook.services.greetd.enable;

        soyo-no-workstation-networking =
          !soyo.networking.networkmanager.enable
          && soyo.networking.useNetworkd
          && soyo.systemd.network.enable;
        soyo-no-graphical-environment = graphicalFeaturesDisabled soyo;
        soyo-appliance-role =
          roleMarker soyo == "appliance\n"
          && soyo.services.blocky.enable
          && soyo.services.dnsmasq.enable
          && optionEnabled [ "lanAppliance" "services" "dhcp" "enable" ] soyo;

        base-does-not-select-network-backend =
          !baseOnly.networking.networkmanager.enable
          && !baseOnly.networking.useNetworkd
          && !baseOnly.systemd.network.enable;
        base-does-not-select-swap-policy = !baseOnly.zramSwap.enable;
        base-does-not-select-graphical-environment = graphicalFeaturesDisabled baseOnly;
        base-does-not-claim-a-role = roleMarker baseOnly == null;
        home-base-does-not-select-graphical-session =
          !homeBaseOnly.wayland.windowManager.sway.enable && !homeBaseOnly.xsession.enable;
        home-base-does-not-assume-a-display =
          !(homeBaseOnly.home.sessionVariables ? DISPLAY)
          && !(homeBaseOnly.home.sessionVariables ? WAYLAND_DISPLAY)
          && !(homeBaseOnly.home.sessionVariables ? XDG_SESSION_TYPE)
          && !(homeBaseOnly.home.sessionVariables ? XDG_CURRENT_DESKTOP);
      };

      failed = builtins.attrNames (lib.filterAttrs (_: passed: !passed) testResults);
    in
    {
      checks.host-role-invariants =
        assert
          failed == [ ] || throw "Host role invariant tests failed: ${builtins.concatStringsSep ", " failed}";
        pkgs.runCommand "host-role-invariants-test" { } ''
          touch $out
        '';
    };
}
