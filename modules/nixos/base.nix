{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      time.timeZone = "Europe/Warsaw";
      i18n.defaultLocale = "en_US.UTF-8";
      environment.variables.EDITOR = "nvim";

      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        auto-optimise-store = true;
        warn-dirty = false;
        # trusted-users: required for `nixos-rebuild --target-host` to work.
        # Without this, the remote nix daemon rejects unsigned store paths
        # (from `nix-copy-closure`) when the build adds new packages.
        # Include root, the admin user, and @wheel so any future admin works too.
        trusted-users = [
          "root"
          "krzysiek"
          "@wheel"
        ];
      };

      documentation.nixos.enable = true;

      programs.neovim = {
        enable = true;
        viAlias = true;
      };

      environment.systemPackages = with pkgs; [
        git
        htop
        jq
      ];
    };
}
