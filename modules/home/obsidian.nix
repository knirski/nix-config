{
  aspects.homeManager.obsidian =
    {
      pkgs,
      ...
    }:
    let
      vaultPath = "~/Documents/Obsidian/obsidian-personal";
      pluginDir = "${vaultPath}/.obsidian/plugins/hybrid-git-sync";

      plugin = pkgs.fetchFromGitHub {
        owner = "wk-obsidian";
        repo = "HybridGitSync";
        rev = "0013fc9decc0e373293dfee937d9e205f5f750ec";
        hash = "sha256-O8wzn+A3/+OHEINxvCY2gD4mkCogv1BITkUIdP+MGtY=";
      };
    in
    {
      home.file = {
        "Documents/Obsidian/obsidian-personal/.gitignore".text = ''
          .obsidian/
          .git/
          _fit/
        '';

        "${pluginDir}/main.js".source = "${plugin}/main.js";
        "${pluginDir}/manifest.json".source = "${plugin}/manifest.json";
        "${pluginDir}/data.json".text = builtins.toJSON {
          backend = "auto";
          branch = "main";
          gitPath = "git";
          autoSync = true;
          autoSyncInterval = 10;
          syncOnStartup = true;
          syncOnFileChange = true;
          fileChangeDebounce = 5;
          commitMessage = "vault backup: {{date}}";
          pullStrategy = "rebase";
          showNotice = false;
          debug = false;
        };
      };
    };
}
