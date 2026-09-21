{ ... }:

{
  dotfiles.nushell.modules = {
    "renovate".text = ''
export def --wrapped main [...args] {
    with-env { EDITOR: null } {
        ^renovate ...$args
    }
}

export def --wrapped ",rnv" [...args] {
    main ...$args
}
    ''
  };

  dotfiles.nushell.autoload = {
    "renovate".text = ''
use ../modules/renovate.nu *
    ''
  };
}
