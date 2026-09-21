{ ... }:

{
  dotfiles.nushell.modules = {
    "ls".text = ''
export def --wrapped ",l" [...args] {
    ^ls ...$args
}

export def --wrapped ",lt" [...args] {
    ^ls -lat ...$args
}
    ''
  };

  dotfiles.nushell.autoload = {
    "ls".text = ''
use ../modules/ls.nu *
    ''
  };
}
