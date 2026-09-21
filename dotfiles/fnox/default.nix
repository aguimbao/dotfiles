{ config, lib, pkgs, ... }:

let
  profilesCfg = config.dotfiles.fnox.profiles;

  toml = pkgs.formats.toml { };
  fnoxConfig = toml.generate "fnox-config.toml" {
    env = "exec";
    providers.protonpass.type = "proton-pass";
    profiles = lib.mapAttrs (_: p: {
      secrets = lib.mapAttrs (_: s: { inherit (s) provider value; }) p.secrets;
    }) profilesCfg;
  };

  globalDir = ".local/share/proton-pass-cli";

  fnoxModule = ''
    export def --wrapped _fnox-run [
      --profile (-p): oneof<string, list<string>>
      cmd: string
      ...args: string
    ] {
      if $profile == null or ($profile | describe | str starts-with "bool") {
        error make { msg: "--profile requires a value: -p dev or -p [dev prod]" }
      }

      let profiles = (
        if ($profile | describe | str starts-with "list") {
          $profile
        } else {
          $profile
          | str replace -a '[' "" | str replace -a ']' ""
          | split row -r ',|\s+'
          | where {|p| $p != "" }
        }
      )

      if ($profiles | is-empty) {
        error make { msg: "no profiles given" }
      }

      let global_config = ($env.HOME | path join ".config" "fnox" "config.toml")
      let global_dir = ($env.HOME | path join "${globalDir}")
      let profile_args = ($profiles | each {|p| ['-P', $p] } | flatten)

      let is_tree = (try { $env.PROTON_PASS_USE_GLOBAL_SESSION_DIR_TREE? | into bool } catch { false })
      let is_single = (try { $env.PROTON_PASS_USE_GLOBAL_SESSION_DIR? | into bool } catch { false })

      if $is_tree {
        with-env { PROTON_PASS_SESSION_DIR: $global_dir } {
          ^fnox -c $global_config exec ...$profile_args -- $cmd ...$args
        }
      } else if $is_single {
        let export_res = (with-env { PROTON_PASS_SESSION_DIR: $global_dir } {
          do { ^fnox -c $global_config export --if-missing error --all ...$profile_args --format json } | complete
        })
        if $export_res.exit_code != 0 {
          error make { msg: $"fnox global secret resolution failed: ($export_res.stderr | str trim)" }
        }
        let secrets = ($export_res.stdout | from json | get -o secrets | default {})
        with-env ($secrets | merge { PROTON_PASS_USE_GLOBAL_SESSION_DIR: null }) {
          ^$cmd ...$args
        }
      } else {
        let export_res = (do { ^fnox export --if-missing error --all ...$profile_args --format json } | complete)
        if $export_res.exit_code == 0 {
          ^fnox exec ...$profile_args -- $cmd ...$args
        } else {
          let global_res = (with-env { PROTON_PASS_SESSION_DIR: $global_dir } {
            do { ^fnox -c $global_config export --if-missing error --all ...$profile_args --format json } | complete
          })
          if $global_res.exit_code == 0 {
            let secrets = ($global_res.stdout | from json | get -o secrets | default {})
            with-env $secrets {
              ^$cmd ...$args
            }
          } else {
            error make { msg: $"fnox secret resolution failed: ($export_res.stderr | str trim)" }
          }
        }
      }
    }
  '';

  setupModule = ''
    export def __dotfiles_setup_pass_cli [] {
      mkdir ($env.HOME | path join "${globalDir}")
      let token = (input --suppress-output "Proton Pass Personal Access Token: ")
      with-env { PROTON_PASS_PERSONAL_ACCESS_TOKEN: $token } {
        ^pass-cli login | complete | get stdout | print
      }
    }
  '';
in
{
  options.dotfiles.fnox.profiles = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            provider = lib.mkOption { type = lib.types.str; default = "protonpass"; };
            value = lib.mkOption { type = lib.types.str; description = "Proton Pass path (Vault/Item/Field)."; };
          };
        });
        default = {};
      };
    });
    default = {};
    description = "Fnox profiles. Rendered to fnox/config.toml; wrappers call _fnox-run -p <profile>.";
  };

  config = {
    home.packages = [ pkgs.fnox ];

    xdg.configFile."fnox/config.toml".source = fnoxConfig;

    dotfiles.nushell.alias.aliases."setup-pass-cli" = "__dotfiles_setup_pass_cli";

    dotfiles.nushell.modules = {
      "fnox".text = fnoxModule;
      "fnox-setup".text = setupModule;
    };

    dotfiles.nushell.fragments = {
      setupCommands = [ "__dotfiles_setup_pass_cli" ];
    };
  };
}
