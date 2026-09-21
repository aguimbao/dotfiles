{ ... }:

{
  dotfiles.nushell.modules = {
  };

  dotfiles.nushell.autoload = {
    "carapace".text = ''
$env.CARAPACE_BRIDGES = 'fish,bash,inshellisense'

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
    ''
  };
}
