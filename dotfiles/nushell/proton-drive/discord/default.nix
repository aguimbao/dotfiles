{ config, ... }:

{
  dotfiles.nushell.proton-drive.backups.discord = {
    source = "${config.home.homeDirectory}/.config/discord";
    archiveName = "discord__config.tar.gz";
  };
}
