{
  aspects.homeManager.base =
    { pkgs, lib, ... }:
    {
      home = {
        sessionVariables = {
          EDITOR = "nvim";
        };
        packages = with pkgs; [
          command-code
          # Modern CLI replacements (no HM modules)
          du-dust
          sd
          yq
          hyperfine
          ncdu
          dogdns
          # Security tools
          age
          # Shell enhancements
          tldr
        ];
      };

      programs = {
        atuin = {
          enable = true;
          enableZshIntegration = true;
        };
        bat.enable = true;
        btop.enable = true;
        codex.enable = true;
        delta.enable = true;
        eza = {
          enable = true;
          enableZshIntegration = true;
        };
        fd.enable = true;
        fzf = {
          enable = true;
          enableZshIntegration = true;
        };
        gh = {
          enable = true;
          extensions = with pkgs; [ gh-dash ];
        };
        gpg.enable = true;
        lazygit.enable = true;
        mc.enable = true;
        navi = {
          enable = true;
          enableZshIntegration = true;
        };
        nnn.enable = true;
        opencode.enable = true;
        procs.enable = true;
        ripgrep.enable = true;
        tmux.enable = true;
        zoxide = {
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

      services.gpg-agent = lib.optionalAttrs pkgs.stdenv.isLinux {
        enable = true;
        enableZshIntegration = true;
      };
    };
}
