{
  aspects.homeManager.base =
    { pkgs, ... }:
    {
      home = {
        stateVersion = "26.05";
        sessionVariables = {
          EDITOR = "nvim";
        };
        packages = with pkgs; [
          fd
          ripgrep
          tmux
          gh
          command-code
        ];
      };

      programs = {
        bash.enable = true;
        git.enable = true;
        home-manager.enable = true;
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}
