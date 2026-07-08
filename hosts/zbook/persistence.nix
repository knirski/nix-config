{
  preservation.preserveAt."/persist" = {
    directories = [
      {
        directory = "/var/lib/nixos";
        inInitrd = true;
      }
      {
        directory = "/etc/ssh";
        inInitrd = true;
      }
      "/var/lib/tailscale"
      "/var/log"
    ];
    files = [
      {
        file = "/etc/machine-id";
        inInitrd = true;
      }
    ];
    users.krzysiek = {
      directories = [
        {
          directory = ".ssh";
          mode = "0700";
        }
        ".local/share/direnv"
        ".config"
        ".commandcode"
        "tmp"
        "github"
        "Downloads"
        "Documents"
        "Pictures"
        "Music"
        "Videos"
        ".local/share/Steam"
        ".local/share/lutris"
      ];
      files = [
        ".bash_history"
        ".zsh_history"
      ];
    };
  };
}
