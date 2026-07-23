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

      # Purely-for-evaluation Darwin fixture mirroring how macbook.nix
      # actually assembles the host: home-manager's own darwin-capable
      # homeManagerConfiguration, base + aerospace (macbook's real WM
      # aspect), aarch64-darwin. This only needs to *evaluate* — no builder
      # for aarch64-darwin exists here, and nothing below forces a build.
      darwinBaseOnly =
        (inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs-unstable {
            system = "aarch64-darwin";
          };
          modules = [
            config.aspects.homeManager.base
            config.aspects.homeManager.aerospace
            {
              home = {
                username = "krzysiek";
                homeDirectory = "/Users/krzysiek";
                stateVersion = "26.05";
              };
            }
          ];
        }).config;

      roleMarker = host: host.environment.etc."nix-config/role".text or null;
      optionEnabled = path: host: lib.attrByPath path false host;
      graphicalFeaturesDisabled =
        host: !host.services.xserver.enable && !host.services.greetd.enable && !host.programs.sway.enable;

      # Development/agent tooling that must be confined to
      # aspects.homeManager.development (zbook, macbook, ubuntu) and must
      # never reach soyo, a headless appliance with no docker and no GitHub
      # workflow. Checked against the evaluated `home.packages` names (pname
      # falling back to name) so this survives version bumps.
      developmentPackageNames = [
        "command-code"
        "nil"
        "nixd"
        "lua-language-server"
        "pyright"
        "typescript-language-server"
        "rust-analyzer"
        "gopls"
        "nushell"
      ];
      packageNames = pkgList: map (p: p.pname or p.name or "") pkgList;
      homeHasNoDevelopmentPackages =
        home:
        let
          names = packageNames home.home.packages;
        in
        builtins.all (n: !(builtins.elem n names)) developmentPackageNames;
      homeHasDevelopmentPackages =
        home:
        let
          names = packageNames home.home.packages;
        in
        builtins.all (n: builtins.elem n names) developmentPackageNames;
      developmentProgramsDisabled =
        home:
        !(home.programs.claude-code.enable or false)
        && !(home.programs.codex.enable or false)
        && !(home.programs.opencode.enable or false)
        && !(home.programs.docker-cli.enable or false)
        && !(home.programs.lazydocker.enable or false);
      developmentProgramsEnabled =
        home:
        (home.programs.claude-code.enable or false)
        && (home.programs.codex.enable or false)
        && (home.programs.opencode.enable or false)
        && (home.programs.docker-cli.enable or false)
        && (home.programs.lazydocker.enable or false);

      # Name of a package option value that may legitimately be null
      # (services.gpg-agent.pinentry.package is nullable — unset on hosts/
      # platforms where the whole gpg-agent block is guarded off). Falls
      # back to "" so callers can use lib.hasPrefix without a null check.
      pinentryPackageName = pkg: if pkg == null then "" else pkg.pname or pkg.name or "";
      yaziOpenCommand = home: (lib.head home.programs.yazi.settings.opener.open).run;

      soyoHome = soyo.home-manager.users.krzysiek;
      zbookHome = zbook.home-manager.users.krzysiek;
      macbookHome = inputs.self.darwinConfigurations.macbook.config.home-manager.users.krzysiek;
      ubuntuHome = inputs.self.homeConfigurations.ubuntu.config;

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

        # R1: soyo (appliance) must never receive the github-token secret or
        # any development/agent tooling; zbook (workstation) must retain both.
        soyo-no-github-token-secret = !(soyo.age.secrets ? github-token);
        zbook-has-github-token-secret = zbook.age.secrets ? github-token;

        soyo-no-development-packages = homeHasNoDevelopmentPackages soyoHome;
        soyo-no-development-programs = developmentProgramsDisabled soyoHome;

        zbook-has-development-packages = homeHasDevelopmentPackages zbookHome;
        zbook-has-development-programs = developmentProgramsEnabled zbookHome;

        macbook-has-development-packages = homeHasDevelopmentPackages macbookHome;
        macbook-has-development-programs = developmentProgramsEnabled macbookHome;

        ubuntu-has-development-packages = homeHasDevelopmentPackages ubuntuHome;
        ubuntu-has-development-programs = developmentProgramsEnabled ubuntuHome;

        # R2: the headless Linux base (soyo-equivalent — homeBaseOnly has no
        # desktop aspect imported) must get a terminal-safe pinentry, never
        # the GUI one, since there is no D-Bus/graphical session to display
        # it. Compared by derivation name, not by nix-store identity, so
        # this survives version bumps.
        headless-base-rejects-gnome-pinentry =
          !(lib.hasPrefix "pinentry-gnome3" (
            pinentryPackageName homeBaseOnly.services.gpg-agent.pinentry.package
          ));
        headless-base-uses-terminal-pinentry = lib.hasPrefix "pinentry-curses" (
          pinentryPackageName homeBaseOnly.services.gpg-agent.pinentry.package
        );
        soyo-rejects-gnome-pinentry =
          !(lib.hasPrefix "pinentry-gnome3" (
            pinentryPackageName soyoHome.services.gpg-agent.pinentry.package
          ));

        # zbook (real Linux desktop host) must still get the GUI pinentry —
        # desktop.nix's override must not have been lost in the base fixup.
        zbook-uses-gnome-pinentry = lib.hasPrefix "pinentry-gnome3" (
          pinentryPackageName zbookHome.services.gpg-agent.pinentry.package
        );

        # R2: Yazi's opener must resolve to the platform-native command —
        # xdg-open on Linux (soyo/zbook), open on Darwin (macbook), never the
        # other one.
        soyo-yazi-opener-is-xdg-open = yaziOpenCommand soyoHome == "xdg-open \"$@\"";
        zbook-yazi-opener-is-xdg-open = yaziOpenCommand zbookHome == "xdg-open \"$@\"";
        macbook-yazi-opener-is-open = yaziOpenCommand macbookHome == "open \"$@\"";
        macbook-yazi-opener-has-no-xdg-open = !(lib.hasInfix "xdg-open" (yaziOpenCommand macbookHome));

        # R2: purely-evaluated Darwin base+aerospace fixture (mirrors
        # macbook.nix's real construction) must contain no Linux-only
        # command/package: no xdg-open, and no pinentry-gnome3 (a Linux/GTK
        # package with no Darwin build) anywhere in the evaluated config.
        darwin-base-yazi-opener-is-open = yaziOpenCommand darwinBaseOnly == "open \"$@\"";
        darwin-base-has-no-xdg-open = !(lib.hasInfix "xdg-open" (yaziOpenCommand darwinBaseOnly));
        darwin-base-rejects-gnome-pinentry =
          !(lib.hasPrefix "pinentry-gnome3" (
            pinentryPackageName darwinBaseOnly.services.gpg-agent.pinentry.package
          ));
        darwin-base-gpg-agent-disabled = !darwinBaseOnly.services.gpg-agent.enable;
        macbook-rejects-gnome-pinentry =
          !(lib.hasPrefix "pinentry-gnome3" (
            pinentryPackageName macbookHome.services.gpg-agent.pinentry.package
          ));
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
