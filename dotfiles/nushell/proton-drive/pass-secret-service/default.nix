{ config, ... }:

{
  dotfiles.nushell.proton-drive.backups.pass-secret-service = {
    source = "${config.home.homeDirectory}/.password-store";
    archiveName = "pass-secret-service__password-store.tar.gz";
  };
}
