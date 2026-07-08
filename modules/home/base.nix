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
        git = {
          enable = true;
          userName = "Krzysztof Nirski";
          userEmail = "krzysztof.nirski+github@gmail.com";
          # HTTPS → SSH rewrite so git uses the SSH remote automatically.
          extraConfig = {
            url."git@github.com:".insteadOf = "https://github.com/";
          };
        };
        home-manager.enable = true;
        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };
      };
    };
}
