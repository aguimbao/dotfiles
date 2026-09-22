{ ... }:

{
  dotfiles.nushell.modules = {
    "system-pass-cli-podman".text = ''
export def --env ",sys setup" [] {
  use ./pass-cli.nu *
  use ./podman.nu *
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
    "system-pass-cli-podman".text = ''
use ../modules/system-pass-cli-podman.nu *
    '';
  };
}
