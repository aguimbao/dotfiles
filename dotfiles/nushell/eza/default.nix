{ ... }:

{
  dotfiles.nushell.modules = {
    "eza".text = ''
export def --wrapped main [...args] {
    ^eza ...$args
}

export def --wrapped ",e" [...args] {
    main -la ...$args
}

export def --wrapped ",et" [...args] {
    main -lars modified ...$args
}
    ''
  };

  dotfiles.nushell.autoload = {
    "eza".text = ''
use ../modules/eza.nu *
    ''
  };
}
