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
        ];
      };

      programs = {
        atuin = {
          enable = true;
          enableZshIntegration = true;
        };
        bat.enable = true;
        bottom.enable = true;
        broot = {
          enable = true;
          enableZshIntegration = true;
        };
        btop.enable = true;
        claude-code.enable = true;
        codex.enable = true;
        command-not-found.enable = true;
        delta.enable = true;
        difftastic.enable = true;
        docker-cli.enable = true;
        eza = {
          enable = true;
          enableZshIntegration = true;
        };
        fastfetch.enable = true;
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
        jq.enable = true;
        lazydocker.enable = true;
        lazygit.enable = true;
        lsd.enable = true;
        mc.enable = true;
        mcfly = {
          enable = true;
          enableZshIntegration = true;
        };
        navi = {
          enable = true;
          enableZshIntegration = true;
        };
        nix-your-shell = {
          enable = true;
          enableZshIntegration = true;
        };
        nnn.enable = true;
        neovim = {
          enable = true;
          defaultEditor = true;
          viAlias = true;
          vimAlias = true;
          plugins = with pkgs.vimPlugins; [
            # LSP
            nvim-lspconfig
            # Treesitter
            (nvim-treesitter.withPlugins (p: [
              p.nix
              p.lua
              p.python
              p.javascript
              p.typescript
              p.rust
              p.go
              p.bash
              p.json
              p.yaml
              p.toml
              p.markdown
            ]))
            # Completion
            nvim-cmp
            cmp-nvim-lsp
            cmp-buffer
            cmp-path
            # Fuzzy finder
            telescope-nvim
            plenary-nvim
            # File explorer
            neo-tree-nvim
            # Status line
            lualine-nvim
            # Git integration
            gitsigns-nvim
            # Theme
            catppuccin-nvim
          ];
          extraLuaConfig = ''
            -- Basic settings
            vim.opt.number = true
            vim.opt.relativenumber = true
            vim.opt.termguicolors = true
            vim.opt.signcolumn = "yes"
            vim.opt.updatetime = 250
            vim.opt.clipboard = "unnamedplus"

            -- Keymaps
            vim.g.mapleader = " "
            vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
            vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>")
            vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>")
            vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>")

            -- LSP
            local lspconfig = require('lspconfig')
            local capabilities = require('cmp_nvim_lsp').default_capabilities()

            -- Enable LSP servers
            lspconfig.nil_ls.setup { capabilities = capabilities }  -- Nix
            lspconfig.lua_ls.setup { capabilities = capabilities }   -- Lua
            lspconfig.pyright.setup { capabilities = capabilities }  -- Python
            lspconfig.ts_ls.setup { capabilities = capabilities }    -- TypeScript/JavaScript
            lspconfig.rust_analyzer.setup { capabilities = capabilities }  -- Rust
            lspconfig.gopls.setup { capabilities = capabilities }    -- Go

            -- Completion
            local cmp = require('cmp')
            cmp.setup({
              sources = {
                { name = 'nvim_lsp' },
                { name = 'buffer' },
                { name = 'path' },
              },
              mapping = cmp.mapping.preset.insert({
                ['<C-n>'] = cmp.mapping.select_next_item(),
                ['<C-p>'] = cmp.mapping.select_prev_item(),
                ['<CR>'] = cmp.mapping.confirm({ select = true }),
                ['<C-Space>'] = cmp.mapping.complete(),
              }),
            })

            -- Theme
            vim.cmd.colorscheme "catppuccin"
          '';
        };
        opencode.enable = true;
        procs.enable = true;
        ripgrep.enable = true;
        skim = {
          enable = true;
          enableZshIntegration = true;
        };
        tealdeer.enable = true;
        thefuck = {
          enable = true;
          enableZshIntegration = true;
        };
        tmux = {
          enable = true;
          mouse = true;
          keyMode = "vi";
          terminal = "tmux-256color";
          extraConfig = ''
            # Use vi-style navigation
            bind h select-pane -L
            bind j select-pane -D
            bind k select-pane -U
            bind l select-pane -R

            # Split panes with | and -
            bind | split-window -h
            bind - split-window -v

            # Clipboard integration
            set -g set-clipboard on
            set -ag terminal-overrides ',xterm-256color:Ms=\E]52;c;%p2%s\007'

            # Status bar
            set -g status-style 'bg=#333333 fg=#5eacd3'
            set -g status-left-length 50
            set -g status-right-length 100
            set -g status-left '#[fg=green]#S '
            set -g status-right '#[fg=yellow]%Y-%m-%d #[fg=green]%H:%M'

            # Start windows and panes at 1
            set -g base-index 1
            setw -g pane-base-index 1
          '';
        };
        yazi = {
          enable = true;
          enableZshIntegration = true;
        };
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
            user = {
              name = "Krzysztof Nirski";
              email = "krzysztof.nirski+github@gmail.com";
              signingkey = "~/.ssh/id_ed25519";
            };
            init.defaultBranch = "main";
            pull.rebase = true;
            push.autoSetupRemote = true;
            merge.conflictstyle = "diff3";
            diff.colorMoved = "default";
            # Use delta as pager
            core.pager = "delta";
            interactive.diffFilter = "delta --color-only";
            delta = {
              navigate = true;
              light = false;
              line-numbers = true;
            };
            # SSH commit signing
            commit.gpgsign = true;
            gpg.format = "ssh";
            # Useful aliases
            alias = {
              lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
              st = "status";
              co = "checkout";
              br = "branch";
              ci = "commit";
              unstage = "reset HEAD --";
              last = "log -1 HEAD";
              visual = "!gitk";
            };
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
