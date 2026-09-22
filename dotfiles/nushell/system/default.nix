{ ... }:

{
  dotfiles.nushell.envExtra = [
    ''
      $env.DOTFILES_DIR = ($env.DOTFILES_DIR? | default ($env.HOME | path join "dotfiles"))
    ''
  ];
}
