{ config, lib, ... }:

let
  bridges = lib.sort lib.lessThan (lib.unique ([ "bash" ] ++ config.dotfiles.nushell.carapace.bridges));
in
{
  options.dotfiles.nushell.carapace.bridges = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Extra carapace bridge programs. bash is ambient and always included; fish/inshellisense nodes append their own entry.";
  };

  config.dotfiles.nushell.autoload = {
    "carapace".text = ''
$env.CARAPACE_BRIDGES = '${lib.concatStringsSep "," bridges}'

let carapace_completer = {|spans: list<string>|
    carapace $spans.0 nushell ...$spans | from json
}

$env.config = ($env.config? | default {} | merge {
    completions: {
        external: {
            enable: true
            max_results: 100
            completer: $carapace_completer
        }
    }
})
    '';
  };
}
