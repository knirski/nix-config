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
      githubTokenShellInit = lib.optionalString pkgs.stdenv.isLinux ''
        if [ -r /run/agenix/github-token ]; then
          export GITHUB_TOKEN="$(cat /run/agenix/github-token)"
          export GH_TOKEN="$GITHUB_TOKEN"
        fi
      '';
    in
    {
      home.packages = with pkgs; [
        command-code
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
      ];

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
        # none). desktop.nix layers gh-dash/gh-pr-review extensions on top of
        # this on hosts that also enable the desktop aspect.
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

        bash.initExtra = githubTokenShellInit;
        # Home Manager's zsh module concatenates every module's initContent
        # into ~/.zshrc, same as bash.initExtra above.
        zsh.initContent = githubTokenShellInit;
      };
    };
}
