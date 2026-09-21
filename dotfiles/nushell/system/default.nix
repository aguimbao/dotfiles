{ ... }:

{
  dotfiles.nushell.envExtra = [
    ''
      $env.DOTFILES_DIR = ($env.DOTFILES_DIR? | default ($env.HOME | path join "dotfiles"))
    ''
  ];

  dotfiles.nushell.modules = {
    "system".text = ''
use ./pass-cli.nu *
use ./podman.nu *

export def --env ",sys setup" [] {
  cd
  ,pc pat-login-purge
  ,pc pat-login
  ,pc ssh-keys-load
  sudo nixos-rebuild switch --flake $env.DOTFILES_DIR
  ,pm system-prune
  cd -
}
    '';
  };

  dotfiles.nushell.autoload = {
    "system".text = ''
use ../modules/system.nu *
    '';
  };
}
