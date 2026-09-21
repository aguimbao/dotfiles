{ config, lib, pkgs, manifest, ... }:

let
  cfg = config.dotfiles.nushell.proton-drive.backups;

  allMods = builtins.attrNames config.dotfiles.nushell.modules;
  useHeader = lib.concatStringsSep "\n"
    (map (k: "use ../modules/${k}.nu *")
      (builtins.filter (k: k != "proton-drive" && k != "__dotfiles_all") allMods));

  remoteRoot = "/Dev/dotfiles/${manifest."configuration-id"}";

  backupFragments = lib.mapAttrsToList (name: spec: ''
    ${useHeader}
    export def __dotfiles_backup_${name} [] {
${spec.preBackup}
      let source = "${spec.source}"
      let parent = ($source | path dirname)
      let dir = ($source | path basename)
      let archive = "${spec.archiveName}"
      let tar = ($archive | str replace --regex '\\.gz$' "")
      let tmp = (^mktemp -d | str trim)
      ^${pkgs.gnutar}/bin/tar -cf $"($tmp)/($tar)" -C $parent $dir
      ^${pkgs.gzip}/bin/gzip $"($tmp)/($tar)"
      ^proton-drive filesystem upload $"($tmp)/($archive)" "${remoteRoot}/${spec.remoteName}/backup" --json
${spec.postBackup}
      rm -rf $tmp
    }
  '') cfg;

  restoreFragments = lib.mapAttrsToList (name: spec: ''
    ${useHeader}
    export def __dotfiles_restore_${name} [] {
${spec.preSetup}
      let remote = "${remoteRoot}/${spec.remoteName}/backup/${spec.archiveName}"
      let source = "${spec.source}"
      let parent = ($source | path dirname)
      let dir = ($source | path basename)
      let archive = "${spec.archiveName}"
      let tar = ($archive | str replace --regex '\\.gz$' "")
      let tmp = (^mktemp -d | str trim)

      let result = (try {
        ^proton-drive filesystem download $remote $"($tmp)/($archive)" --json
        true
      } catch {
        false
      })

      if $result {
        ^${pkgs.gzip}/bin/gzip -d $"($tmp)/($archive)"
        ^${pkgs.gnutar}/bin/tar -xf $"($tmp)/($tar)" -C $tmp
${spec.preRestore}
        if not ($"($tmp)/($dir)" | path exists) {
          print "Backup ${name}: extracted dir missing, keeping local data"
        } else {
          ^mkdir -p $parent
          rm -rf $source
          ^mv $"($tmp)/($dir)" $source
        }
${spec.postRestore}
      } else {
        print "No ${name} backup found, skipping restore"
      }

${spec.postSetup}
      rm -rf $tmp
    }
  '') cfg;

  filtered = lib.filterAttrs (_: spec: spec.includeInAll) cfg;

  backupAliases = lib.mapAttrs' (name: _:
    lib.nameValuePair "backup-${name}" "__dotfiles_backup_${name}"
  ) filtered;

  restoreAliases = lib.mapAttrs' (name: _:
    lib.nameValuePair "setup-${name}" "__dotfiles_restore_${name}"
  ) filtered;

  backupCmds = lib.mapAttrsToList (name: _: "__dotfiles_backup_${name}") filtered;
  restoreCmds = lib.mapAttrsToList (name: _: "__dotfiles_restore_${name}") filtered;
in
{
  dotfiles.nushell.alias.aliases = backupAliases // restoreAliases;

  dotfiles.nushell.modules = {
    "proton-drive".text = lib.concatStringsSep "\n\n" (backupFragments ++ restoreFragments);
  };

  dotfiles.nushell.fragments = {
    setupCommands = restoreCmds;
    backupCommands = backupCmds;
  };
}
