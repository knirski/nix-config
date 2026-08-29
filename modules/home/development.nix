# Home Manager aspect: development — AI coding agents, language servers, and
# other developer-only tooling that a headless appliance (soyo) has no
# legitimate use for.
#
# Enabled on zbook, macbook, and ubuntu (workstation/developer hosts).
# Deliberately NOT enabled on soyo: it has no docker, no GitHub workflow, and
# no recovery need for an AI coding agent or a language server.
{
  aspects.homeManager.development =
    {
      pkgs,
      lib,
      ...
    }:
    let
      # Bash and Zsh must behave identically: only export GITHUB_TOKEN/GH_TOKEN
      # when the (workstation-only) secret has actually been rekeyed onto this
      # host, and only read the file at shell-start time, never at evaluation
      # time.
      githubTokenShellInit = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        if [ -r /run/agenix/github-token ]; then
          export GITHUB_TOKEN="$(cat /run/agenix/github-token)"
          export GH_TOKEN="$GITHUB_TOKEN"
        fi
      '';
      # Wrapper around `nix flake update` that passes the GitHub token for
      # authenticated API requests (avoids the 60 req/h unauthenticated rate
      # limit). Falls back to plain `nix flake update` when the secret is
      # absent (e.g. soyo, or before first deploy).
      nfuWithToken = lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
        nfu() {
          if [ -n "''${GITHUB_TOKEN:-}" ]; then
            NIX_CONFIG="access-tokens = github.com=$GITHUB_TOKEN" nix flake update "$@"
          else
            nix flake update "$@"
          fi
        }
      '';
      # Keep the IDE and SDK separate: the IDE is a Linux-only binary, while
      # the SDK is also useful to Gradle and command-line Android tooling.
      # The host assemblers explicitly accept the SDK license where this
      # package is enabled.
      androidSdkComposition = import ../../lib/android-sdk.nix { inherit pkgs; };
      androidSdk = androidSdkComposition.androidsdk;
    in
    {
      home.packages =
        with pkgs;
        [
          jetbrains.idea
          vscode
          antigravity-ide
          antigravity-cli
          command-code
          # Rust Token Killer — CLI proxy that filters git/grep/find output
          # before it reaches an AI coding agent's context.
          rtk
          # Browser automation for AI agents (CDP + a11y tree, sessions, auth
          # vault). Nixpkgs build embeds dashboard/skills next to bin/.
          agent-browser
          # Nix language servers
          nil
          nixd
          # Language servers for neovim (see programs.neovim.extraPackages below)
          lua-language-server
          pyright
          typescript-language-server
          rust-analyzer
          gopls
          # Used by AI coding agents (claude-code, codex, opencode, command-code)
          # for script execution — not an interactive admin shell.
          nushell
          # github
          actionlint
          nodejs
          # AWS command-line client for workstation cloud administration.
          awscli2
        ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [
          android-studio
          androidSdk
        ];

      home.sessionVariables = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
        ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
      };

      programs = {
        claude-code.enable = true;
        codex.enable = true;
        opencode.enable = true;

        direnv = {
          enable = true;
          nix-direnv.enable = true;
        };

        docker-cli.enable = true;
        lazydocker.enable = true;
        lazygit = {
          enable = true;
          settings = {
            # Catppuccin Mocha theme colors
            gui.theme = {
              activeBorderColor = [
                "#89b4fa" # Blue
                "bold"
              ];
              inactiveBorderColor = [ "#a6adc8" ]; # Overlay0
              searchingActiveBorderColor = [
                "#f9e2af" # Yellow
                "bold"
              ];
              selectedLineBgColor = [ "#313244" ]; # Surface0
              cherryPickedCommitFgColor = [ "#89dceb" ]; # Teal
              cherryPickedCommitBgColor = [ "#45475a" ]; # Surface1
            };
            git = {
              paging = {
                colorArg = "always";
                pager = "delta --dark --paging=never"; # Use delta for syntax highlighting
              };
              commit = {
                signOff = true; # Add Signed-off-by line
              };
            };
          };
        };

        # GitHub CLI: no legitimate use without a GitHub workflow (soyo has
        # none). desktop.nix layers gh-dash/gh-pr-review/gh-stack extensions
        # on top of this on hosts that also enable the desktop aspect.
        gh = {
          enable = true;
          settings = {
            editor = "nvim";
            git_protocol = "ssh";
            prompt = "enabled";
          };
        };

        # LSP support for neovim (base.nix keeps neovim itself as a
        # general-purpose editor; the language-server integration is
        # developer-only tooling).
        neovim = {
          plugins = with pkgs.vimPlugins; [
            nvim-lspconfig
            cmp-nvim-lsp # LSP source for nvim-cmp
          ];
          extraPackages = with pkgs; [
            nil
            lua-language-server
            pyright
            typescript-language-server
            rust-analyzer
            gopls
          ];
          initLua = ''
            -- LSP using the new vim.lsp.config API (nvim-lspconfig 2.10+, Neovim 0.11+)
            -- See :help lspconfig-nvim-0.11
            local capabilities = require('cmp_nvim_lsp').default_capabilities()

            -- Configure LSP servers
            vim.lsp.config.nil_ls = { capabilities = capabilities }  -- Nix
            vim.lsp.config.lua_ls = { capabilities = capabilities }   -- Lua
            vim.lsp.config.pyright = { capabilities = capabilities }  -- Python
            vim.lsp.config.ts_ls = { capabilities = capabilities }    -- TypeScript/JavaScript
            vim.lsp.config.rust_analyzer = { capabilities = capabilities }  -- Rust
            vim.lsp.config.gopls = { capabilities = capabilities }    -- Go

            -- Enable all configured LSP servers
            vim.lsp.enable({
              'nil_ls',
              'lua_ls',
              'pyright',
              'ts_ls',
              'rust_analyzer',
              'gopls',
            })
          '';
        };

        bash.initExtra = githubTokenShellInit + nfuWithToken;
        # Home Manager's zsh module concatenates every module's initContent
        # into ~/.zshrc, same as bash.initExtra above.
        zsh.initContent = githubTokenShellInit + nfuWithToken;
      };
    };
}
