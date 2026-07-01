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
        trusted-users = [
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
