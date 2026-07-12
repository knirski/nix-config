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
          codex
        ];
      };

      programs = {
        starship = {
          enable = true;
          settings = {
            add_newline = false;
            cmd_duration.show_milliseconds = false;
          };
        };
        zsh = {
          enable = true;
          oh-my-zsh = {
            enable = true;
            plugins = [
              "git"
              "docker"
              "docker-compose"
              "sudo"
              "copyfile"
              "dirhistory"
              "extract"
              "history"
              "z"
              "colored-man-pages"
            ];
          };
        };
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
