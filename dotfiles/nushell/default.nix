{ config, lib, pkgs, ... }:

let
  modCfg = config.dotfiles.nushell.modules;
  autoCfg = config.dotfiles.nushell.autoload;
  fragCfg = config.dotfiles.nushell.fragments;
  aliasCfg = config.dotfiles.nushell.alias;

  useAllExcept = exceptKeys:
    lib.concatStringsSep "\n" (map (k: "use ../modules/${k}.nu *")
      (builtins.filter (k: !(builtins.elem k exceptKeys)) (builtins.attrNames modCfg)));

  runner = label: commands:
    ''
      def --env __dotfiles_${label}_all [] {
          let results = [${
            lib.concatMapStringsSep "\n" (cmd: ''
              {
                name: "${cmd}";
                ok: (try { ${cmd}; true } catch { false })
              }'') commands
          }]
          print (run_aggregate_results "${label}" $results)
        }

        def run_aggregate_results [label, results] {
          let ok = ($results | where ok == true)
          let failed = ($results | where ok == false)
          let total = ($results | length)
          let n_ok = ($ok | length)
          let n_failed = ($failed | length)
          let line = (
            $"=== ($label) finished: ($n_ok)/($total) ok, ($n_failed) failed ==="
          )
          if $failed == [] {
            print (^gum style --foreground 2 $line)
          } else {
            print (^gum style --foreground 1 $line)
            let names = ($failed | get name | str join ', ')
            print (^gum style --foreground 1 $"FAILED: ($names)")
          }
          if $n_failed > 0 { exit 1 }
        }
      '';

  setupRunner = lib.optionalString (fragCfg.setupCommands != []) (runner "setup" fragCfg.setupCommands);
  backupRunner = lib.optionalString (fragCfg.backupCommands != []) (runner "backup" fragCfg.backupCommands);
  initRunner = lib.optionalString (fragCfg.initCommands != []) (runner "init" fragCfg.initCommands);

  allRunnerModule = useAllExcept [ "__dotfiles_all" ] + "\n\n"
    + setupRunner
    + (lib.optionalString (backupRunner != "") ("\n\n" + backupRunner))
    + (lib.optionalString (initRunner != "") ("\n\n" + initRunner));

  allAliases = aliasCfg.aliases
    // (lib.optionalAttrs (fragCfg.setupCommands != []) { "setup-all" = "__dotfiles_setup_all"; })
    // (lib.optionalAttrs (fragCfg.backupCommands != []) { "backup-all" = "__dotfiles_backup_all"; })
    // (lib.optionalAttrs (fragCfg.initCommands != []) { "init-all" = "__dotfiles_init_all"; });

  aliasesFile = useAllExcept [ ] + "\n\n"
    + lib.concatStringsSep "\n" (lib.mapAttrsToList (n: c: "alias ${n} = ${c}") allAliases);

  stockConfig = ''
    # config.nu
    #
    # Installed by:
    # version = "0.113.0"
    #
    # This file is used to override default Nushell settings, define
    # (or import) custom commands, or run any other startup tasks.
    # See https://www.nushell.sh/book/configuration.html
    #
    # Nushell sets "sensible defaults" for most configuration settings,
    # so your `config.nu` only needs to override these defaults if desired.
    #
    # You can open this file in your default editor using:
    #     config nu
    #
    # You can also pretty-print and page through the documentation for configuration
    # options using:
    #     config nu --doc | nu-highlight | less -R
  '';

  stockEnv = ''
    # env.nu
    #
    # Installed by:
    # version = "0.113.0"
    #
    # Previously, environment variables were typically configured in `env.nu`.
    # In general, most configuration can and should be performed in `config.nu`
    # or one of the autoload directories.
    #
    # This file is generated for backwards compatibility for now.
    # It is loaded before config.nu and login.nu
    #
    # See https://www.nushell.sh/book/configuration.html
    #
    # Also see `help config env` for more options.
    #
    # You can remove these comments if you want or leave
    # them for future reference.
  '';
in
{
  options.dotfiles.nushell.modules = lib.mkOption {
    type = lib.types.attrsOf lib.types.lines;
    default = {};
    description = "Nushell modules by filename (without .nu). Rendered to ~/.config/nushell/modules/<name>.nu. Keep `export` on definitions.";
  };

  options.dotfiles.nushell.autoload = lib.mkOption {
    type = lib.types.attrsOf lib.types.lines;
    default = {};
    description = "Nushell autoload files by filename (without .nu). Rendered to ~/.config/nushell/autoload/<name>.nu.";
  };

  options.dotfiles.nushell.configExtra = lib.mkOption {
    type = lib.types.listOf lib.types.lines;
    default = [];
    description = "Lines appended to config.nu after stock defaults.";
  };

  options.dotfiles.nushell.envExtra = lib.mkOption {
    type = lib.types.listOf lib.types.lines;
    default = [];
    description = "Lines appended to env.nu after stock defaults.";
  };

  options.dotfiles.nushell.alias.aliases = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = {};
    description = "Nushell aliases (name -> command). Rendered into autoload/__dotfiles_aliases.nu.";
  };

  options.dotfiles.nushell.fragments = {
    setupCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Setup function names that setup-all runs in order. Failures are reported but do not abort the run.";
    };

    backupCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Backup function names that backup-all runs in order. Failures are reported but do not abort the run.";
    };

    initCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Init function names that init-all runs in order. Failures are reported but do not abort the run.";
    };
  };

  config = {
    home.packages = [ pkgs.nushell ];

    xdg.configFile =
      (lib.mapAttrs' (n: t: lib.nameValuePair "nushell/modules/${n}.nu" { text = t; }) modCfg)
      // (lib.mapAttrs' (n: t: lib.nameValuePair "nushell/autoload/${n}.nu" { text = t; }) autoCfg)
      // {
        "nushell/modules/__dotfiles_all.nu".text = allRunnerModule;
        "nushell/autoload/__dotfiles_aliases.nu".text = aliasesFile;
        "nushell/config.nu".text =
          stockConfig + "\n\n" + lib.concatStringsSep "\n\n" config.dotfiles.nushell.configExtra;
        "nushell/env.nu".text =
          stockEnv + "\n\n" + lib.concatStringsSep "\n\n" config.dotfiles.nushell.envExtra;
      };
  };
}
