{
  flake.modules.homeManager.base =
    { pkgs, ... }:
    {
      home.stateVersion = "26.05";
      home.sessionVariables.EDITOR = "nvim";

      programs.bash.enable = true;
      programs.git.enable = true;
      programs.home-manager.enable = true;

      home.packages = with pkgs; [
        fd
        ripgrep
        tmux
      ];
    };
}
