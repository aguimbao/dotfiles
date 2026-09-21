{ config, pkgs, ... }:

{
  dotfiles.nushell.proton-drive.backups.atuin-server = {
    remoteName = "atuin";
    source = "${config.home.homeDirectory}/.local/share/atuin-server";
    archiveName = "atuin__local_share_server.tar.gz";
    preBackup = "      try { ^${pkgs.systemd}/bin/systemctl --user stop atuin-server } catch { }";
    postBackup = "      try { ^${pkgs.systemd}/bin/systemctl --user start atuin-server } catch { }";
    preRestore = "        try { ^${pkgs.systemd}/bin/systemctl --user stop atuin-server } catch { }";
    postRestore = "        try { ^${pkgs.systemd}/bin/systemctl --user start atuin-server } catch { }";
  };
}
