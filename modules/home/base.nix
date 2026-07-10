{
  aspects.homeManager.base =
    { pkgs, ... }:
    {
      home = {
        stateVersion = "26.11";
        sessionVariables = {
          EDITOR = "nvim";
        };
        packages = with pkgs; [
          fd
          ripgrep
          tmux
          gh
          command-code
          codex
        ];
      };

      programs = {
        bash = {
          enable = true;
          initExtra = ''
            if [ -r /run/agenix/github-token ]; then
              export GITHUB_TOKEN="$(cat /run/agenix/github-token)"
              export GH_TOKEN="$GITHUB_TOKEN"
            fi
          '';
        };
        git = {
          enable = true;
          settings = {
            user.name = "Krzysztof Nirski";
            user.email = "krzysztof.nirski+github@gmail.com";
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
