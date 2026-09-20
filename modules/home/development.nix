# Home Manager aspect: development — AI coding agents, language servers, and
# other developer-only tooling that a headless appliance (soyo) has no
# legitimate use for.
#
# Enabled on zbook, macbook, and ubuntu (workstation/developer hosts).
# Deliberately NOT enabled on soyo: it has no docker, no GitHub workflow, and
# no recovery need for an AI coding agent or a language server.
_: {
  config.aspects.homeManager.development =
    {
      config,
      pkgs,
      lib,
      inputs,
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
      opencodeV2 = import ../../lib/opencode-v2.nix {
        opencodeV2 = inputs.opencode-v2.packages.${pkgs.stdenv.hostPlatform.system};
      };
    in
    {
      options = {
        development = {
          enableIntellijIdea = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to install IntelliJ IDEA in the development profile.";
          };

          enableAndroidTools = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to install Android Studio and the Android SDK.";
          };

          manageDockerConfig = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether Home Manager should manage Docker's config.json.";
          };
        };
      };

      config = {
        home.packages =
          with pkgs;
          (lib.optional config.development.enableIntellijIdea jetbrains.idea)
          ++ [
            vscode
            antigravity-ide
            antigravity-cli
            # Rust Token Killer — CLI proxy that filters git/grep/find output
            # before it reaches an AI coding agent's context. Sourced from
            # nixpkgs-unstable (every development host tracks it); no custom
            # package or version pin.
            #
            # OpenCode v2 plugin: rtk's released `rtk init -g --opencode`
            # still installs the v1 plugin shape, which OpenCode >= 2.0.x
            # refuses to load. A hand-migrated v2 plugin lives outside this
            # repo at ~/.config/opencode/plugins/rtk.ts. When a released rtk
            # installs a v2-native plugin, delete that local file and
            # regenerate it with `rtk init -g --opencode`.
            #   https://github.com/rtk-ai/rtk/pull/3899
            #   https://github.com/rtk-ai/rtk/issues/3463
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
            metals
            # Used by AI coding agents (claude-code, codex, opencode)
            # for script execution — not an interactive admin shell.
            nushell
            # github
            actionlint
            nodejs
            # AWS command-line client for workstation cloud administration.
            awscli2
          ]
          ++ lib.optionals (stdenv.hostPlatform.isLinux && config.development.enableAndroidTools) [
            android-studio
            androidSdk
          ];

        home.sessionVariables =
          lib.optionalAttrs (pkgs.stdenv.hostPlatform.isLinux && config.development.enableAndroidTools)
            {
              ANDROID_HOME = "${androidSdk}/libexec/android-sdk";
              ANDROID_SDK_ROOT = "${androidSdk}/libexec/android-sdk";
            };

        programs = {
          claude-code.enable = true;
          codex.enable = true;
          opencode = {
            enable = true;
            # OpenCode v2, built by the upstream v2 flake rather than nixpkgs
            # (which still packages v1.x) — see lib/opencode-v2.nix. Hosts get
            # `inputs` through home-manager.extraSpecialArgs.
            package = opencodeV2.opencode;
          };

          direnv = {
            enable = true;
            nix-direnv.enable = true;
          };

          # Ubuntu keeps an operator-managed ~/.docker/config.json symlink for
          # credentials. Home Manager's docker-cli module writes config.json,
          # so the Ubuntu assembler disables this management explicitly.
          docker-cli.enable = config.development.manageDockerConfig;
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
              metals
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
              vim.lsp.config.metals = { capabilities = capabilities }   -- Scala

              -- Enable all configured LSP servers
              vim.lsp.enable({
                'nil_ls',
                'lua_ls',
                'pyright',
                'ts_ls',
                'rust_analyzer',
                'gopls',
                'metals',
              })
            '';
          };

          bash.initExtra = githubTokenShellInit + nfuWithToken;
          # Home Manager's zsh module concatenates every module's initContent
          # into ~/.zshrc, same as bash.initExtra above.
          zsh.initContent = githubTokenShellInit + nfuWithToken;
        };
      };
    };
}
