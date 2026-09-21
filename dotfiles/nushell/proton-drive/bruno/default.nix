{ config, ... }:

{
  dotfiles.nushell.proton-drive.backups.bruno = {
    source = "${config.home.homeDirectory}/.config/bruno";
    archiveName = "bruno__config.tar.gz";
  };
}
