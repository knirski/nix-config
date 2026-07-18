{
  aspects.homeManager.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      home = {
        sessionVariables = {
          EDITOR = "nvim";
        };
        packages = with pkgs; [
          command-code
          gcx
          # Nix language servers for Zed
          nil
          nixd
          # Modern CLI replacements (no HM modules)
          dust
          sd
          yq
          hyperfine
          ncdu
          doggo
          # Security tools
          age
          # Other tools without HM modules
          procs
          unrar # for extract() function
          nushell # used by all agents for script execution
        ];

        # oh-my-zsh plugins (docker, docker-compose) try to overwrite their
        # cached completion files on every shell start. The source files in the
        # nix store are 0444, and `cp` preserves that mode, leaving the cached
        # copies read-only. This makes the subsequent overwrite attempt fail
        # with "Permission denied" on every terminal open.
        # https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/docker/docker.plugin.zsh
        activation.ensureOhMyZshCacheWritable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [ -d "${config.xdg.cacheHome}/oh-my-zsh" ]; then
            chmod -R u+w "${config.xdg.cacheHome}/oh-my-zsh"
          fi
        '';
      };

      programs = {
        atuin = {
          enable = true;
          enableZshIntegration = true;
          # Let fzf own Ctrl-R for interactive search; atuin still syncs
          # history and works via up-arrow search.
          flags = [ "--disable-ctrl-r" ];
          # Up-arrow searches only commands run in the current directory,
          # while Ctrl-R (fzf) searches everything.
          # forceOverwriteSettings ensures the settings below take effect
          # even if Atuin already wrote a default config.toml (Atuin
          # auto-generates one after the first shell command). The trade-off
          # is that any manually-added sync or server settings in that file
          # (e.g. from `atuin login`) will be overwritten — re-run `atuin login`
          # after config changes if you use sync.
          forceOverwriteSettings = true;
          settings = {
            filter_mode_shell_up_key_binding = "directory";
            enter_accept = true;
          };
        };
        bat.enable = true;
        bottom.enable = true;
        broot = {
          enable = true;
          enableZshIntegration = true;
        };
        btop = {
          enable = true;
          settings = {
            # Catppuccin Mocha theme for consistent look with other tools
            color_theme = "catppuccin_mocha";
            theme_background = false;
            truecolor = true;
            rounded_corners = true;
            graph_symbol = "braille"; # Braille characters for smooth graphs
            shown_boxes = "cpu mem net proc";
            cpu_graph_upper = "total"; # Show total CPU usage
            cpu_graph_lower = "total";
            cpu_invert_lower = true; # Invert lower graph for visual clarity
            cpu_single_graph = false;
            show_gpu_info = "on"; # Show GPU temperature (NVIDIA)
            temp_scale = "celsius";
            update_ms = 1000; # 1-second refresh rate
          };
        };
        claude-code.enable = true;
        codex.enable = true;
        command-not-found.enable = false;
        delta.enable = true;
        difftastic.enable = true;
        docker-cli.enable = true;
        eza = {
          enable = true;
          enableZshIntegration = true;
        };
        fastfetch = {
          enable = true;
          settings = {
            logo = {
              type = "small"; # Small logo for compact output
              padding = {
                top = 1;
                right = 2;
                left = 2;
              };
            };
            display = {
              separator = " → "; # Arrow separator for clean look
            };
            # Show system info in logical groups
            modules = [
              "title"
              "separator"
              "os"
              "kernel"
              "shell"
              "terminal"
              "de"
              "wm"
              "wmtheme"
              "separator"
              "cpu"
              "gpu"
              "memory"
              "disk"
              "separator"
              "localip"
              "battery"
              "locale"
              "break"
              "colors"
            ];
          };
        };
        fd.enable = true;
        fzf = {
          enable = true;
          enableZshIntegration = true;
          # Nushell integration requires fzf >= 0.73.0, but soyo uses
          # nixpkgs stable (release-26.05) which has fzf 0.72.0.
          # Nushell is installed for agent tooling, not as an interactive shell.
          enableNushellIntegration = false;
          # Fzf owns Ctrl-R for history search. The generated shell init
          # binds Ctrl-R to fzf's history widget, overlaying zsh's built-in
          # Ctrl-R reverse-search.
        };
        gh = {
          enable = true;
          settings = {
            editor = "nvim";
            git_protocol = "ssh";
            prompt = "enabled";
          };
        };
        gpg.enable = true;
        jq.enable = true;
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
        # Use eza instead of lsd for file listing
        lsd.enable = false;
        mc.enable = true;
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
            # LSP support for multiple languages
            nvim-lspconfig
            # Treesitter for syntax highlighting and code understanding
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
            # Autocompletion engine
            nvim-cmp
            cmp-nvim-lsp # LSP source for nvim-cmp
            cmp-buffer # Buffer words source
            cmp-path # File path source
            # Fuzzy finder for files, grep, buffers
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
          extraPackages = with pkgs; [
            nil
            lua-language-server
            pyright
            typescript-language-server
            rust-analyzer
            gopls
          ];
          initLua = ''
            -- Basic settings
            vim.opt.number = true
            vim.opt.relativenumber = true
            vim.opt.termguicolors = true
            vim.opt.signcolumn = "yes"
            vim.opt.updatetime = 250

            -- Keymaps
            vim.g.mapleader = " "
            vim.keymap.set("n", "<leader>ff", "<cmd>Telescope find_files<cr>")
            vim.keymap.set("n", "<leader>fg", "<cmd>Telescope live_grep<cr>")
            vim.keymap.set("n", "<leader>fb", "<cmd>Telescope buffers<cr>")
            vim.keymap.set("n", "<leader>e", "<cmd>Neotree toggle<cr>")

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
        ripgrep.enable = true;
        skim = {
          enable = true;
          enableZshIntegration = true;
        };
        tealdeer.enable = true;
        pay-respects = {
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
          settings = {
            manager = {
              show_hidden = true;
              sort_by = "modified";
              sort_dir_first = true;
              linemode = "size";
            };
            opener = {
              edit = [
                {
                  run = "nvim \"$@\"";
                  block = true;
                  desc = "Edit";
                }
              ];
              open = [
                {
                  run = "xdg-open \"$@\"";
                  desc = "Open";
                }
              ];
            };
          };
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
          history = {
            size = 100000;
            save = 100000;
            path = "$HOME/.zsh_history";
            ignoreDups = true;
            ignoreAllDups = true;
            ignoreSpace = true;
            expireDuplicatesFirst = true;
          };
          shellAliases = {
            # Navigation
            ll = "eza -la --icons --git";
            la = "eza -a --icons";
            ls = "eza --icons";
            lt = "eza -la --icons --git --tree --level=2";
            ".." = "cd ..";
            "..." = "cd ../..";
            "...." = "cd ../../..";

            # Git shortcuts
            g = "git";
            gst = "git status";
            gco = "git checkout";
            gcb = "git checkout -b";
            gd = "git diff";
            gds = "git diff --staged";
            gl = "git pull";
            gp = "git push";
            gpf = "git push --force-with-lease";
            gc = "git commit";
            gca = "git commit --amend";
            glog = "git log --oneline --graph --decorate";

            # Nix
            nrs = "sudo nixos-rebuild switch --flake .";
            nrt = "sudo nixos-rebuild test --flake .";
            hms = "home-manager switch --flake .";
            nfu = "nix flake update";
            ndv = "nix develop";

            # System
            df = "duf";
            du = "dust";
            ps = "procs";
            cat = "bat";
            grep = "rg";
            find = "fd";
            top = "btop";
            htop = "btop";
            vim = "nvim";
            vi = "nvim";

            # Docker/Podman
            d = "docker";
            dc = "docker compose";
            dps = "docker ps";
            dex = "docker exec -it";

            # Quick actions
            mkdir = "mkdir -p";
            path = "echo $PATH | tr ':' '\n'";
            ports = "ss -tulnp";
          };
          initContent = ''
            # Custom functions (interactive shells only)
            if [[ $- == *i* ]]; then
              mkcd() { mkdir -p "$1" && cd "$1"; }
              extract() {
                if [ -f "$1" ]; then
                  case "$1" in
                    *.tar.bz2) tar xjf "$1" ;;
                    *.tar.gz) tar xzf "$1" ;;
                    *.tar.xz) tar xJf "$1" ;;
                    *.bz2) bunzip2 "$1" ;;
                    *.rar) unrar x "$1" ;;
                    *.gz) gunzip "$1" ;;
                    *.tar) tar xf "$1" ;;
                    *.tbz2) tar xjf "$1" ;;
                    *.tgz) tar xzf "$1" ;;
                    *.zip) unzip "$1" ;;
                    *.Z) uncompress "$1" ;;
                    *.7z) 7z x "$1" ;;
                    *) echo "'$1' cannot be extracted" ;;
                  esac
                else
                  echo "'$1' is not a valid file"
                fi
              }
              portkill() {
                if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                  ss -tulnp | grep ":$1" | awk '{print $NF}' | grep -oP '\d+' | head -1 | xargs -r sudo kill
                elif [[ "$OSTYPE" == "darwin"* ]]; then
                  lsof -i tcp:"$1" -t | xargs kill
                fi
              }
              weather() { curl -s "wttr.in/$1?format=3"; }
              cheat() { curl -s "cheat.sh/$1"; }
            fi
          '';
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
            core.editor = "nvim";
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
        pinentry.package = pkgs.pinentry-gnome3;
      };

    };
}
