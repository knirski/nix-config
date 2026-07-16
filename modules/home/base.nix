{
  aspects.homeManager.base =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables = {
          EDITOR = "nvim";
        };
        packages = with pkgs; [
          fd
          ripgrep
          tmux
          gh
          gh-dash
          command-code
          codex
          opencode
          nnn
          mc
          # Modern CLI replacements
          lazygit
          btop
          eza
          bat
          fzf
          delta
          zoxide
          du-dust
          procs
          sd
          yq
          hyperfine
          ncdu
          dogdns
          # Security tools
          age
          gnupg
          # Shell enhancements
          atuin
          navi
          tldr
        ];
      };

      programs = {
        atuin = {
          enable = true;
          enableZshIntegration = true;
        };
        navi = {
          enable = true;
          enableZshIntegration = true;
        };
        starship = {
          enable = true;
          settings = {
            add_newline = false;
            cmd_duration.show_milliseconds = false;
          };
        };
        zsh = {
          enable = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
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
          initExtra = lib.optionalString pkgs.stdenv.isLinux ''
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
