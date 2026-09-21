{ config, lib, pkgs, ... }:

let
  syncAtuin = "        ^${pkgs.atuin}/bin/atuin sync";
  setupAtuin = lib.concatStringsSep "\n" [
    "        let username = (^${pkgs.proton-pass-cli}/bin/pass-cli item view --vault-name dotfiles --item-title 'ATUIN' --field 'USERNAME' | str trim)"
    "        let password = (^${pkgs.proton-pass-cli}/bin/pass-cli item view --vault-name dotfiles --item-title 'ATUIN' --field 'PASSWORD' | str trim)"
    "        let key = (^${pkgs.proton-pass-cli}/bin/pass-cli item view --vault-name dotfiles --item-title 'ATUIN' --field 'KEY' | str trim)"
    "        ^${pkgs.atuin}/bin/atuin login -u $username -p $password -k $key"
    syncAtuin
  ];
in
{
  dotfiles.nushell.proton-drive.backups.atuin = {
    source = "${config.home.homeDirectory}/.local/share/atuin";
    archiveName = "atuin__local_share.tar.gz";
    preBackup = syncAtuin;
    postRestore = setupAtuin;
  };
}
