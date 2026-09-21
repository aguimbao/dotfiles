{ lib, ... }:

{
  dotfiles.nushell.envExtra = [
    ''
      $env.PROTON_DRIVE_CREDENTIALS_STORE = "pass"
      $env.PROTON_DRIVE_CACHE_DIR = ($env.HOME | path join ".local" "share" "proton-drive-cli")
    ''
  ];

  dotfiles.nushell.modules = {
    "proton-drive-setup".text = ''
      export def __dotfiles_setup_proton_drive [] {
        print "1. Download proton-drive CLI (baseline build for VMs) and put it on PATH as proton-drive"
        print "2. Running: proton-drive auth login (browser sign-in, session goes to pass store)"
        ^proton-drive auth login
      }
    '';
  };

  dotfiles.nushell.alias.aliases."setup-proton-drive" = "__dotfiles_setup_proton_drive";
  dotfiles.nushell.fragments.setupCommands = [ "__dotfiles_setup_proton_drive" ];
}
