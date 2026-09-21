{ lib, ... }:

{
  options.dotfiles.nushell.proton-drive.backups = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        source = lib.mkOption {
          type = lib.types.str;
          description = "Local directory to back up / restore to (absolute path).";
        };
        remoteName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Remote tool directory under /Dev/dotfiles/<configuration-id>.";
        };
        archiveName = lib.mkOption {
          type = lib.types.str;
          description = "Archive filename stored under the remote backup directory.";
        };
        includeInAll = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether setup-all / backup-all should run this target directly.";
        };
        preSetup = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run before attempting a restore (6-space indent).";
        };
        postSetup = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run after a restore attempt (6-space indent).";
        };
        preBackup = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run before tar+upload (6-space indent).";
        };
        postBackup = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run after upload before temp cleanup (6-space indent).";
        };
        preRestore = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run after archive extraction and before replacing the local source (8-space indent).";
        };
        postRestore = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Nushell commands to run after restore inside the success branch (8-space indent).";
        };
      };
    }));
    default = {};
    description = "Backup targets. Each generates __dotfiles_backup_<name> / __dotfiles_restore_<name> via proton-drive CLI. Remote path is /Dev/dotfiles/<configuration-id>/<remoteName>/backup/<archiveName>.";
  };
}
