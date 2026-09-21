{ pkgs, ... }:

{
  dotfiles.nushell.modules = {
    "hostname".text = ''
      export def new-hostname [] {
        $"HOSTNAME-(^${pkgs.openssl}/bin/openssl rand -hex 4 | str trim | str upcase)"
      }
    '';
    "machine-id".text = ''
      export def new-machine-id [] {
        ^${pkgs.openssl}/bin/openssl rand -hex 16 | str trim
      }
    '';
  };

  dotfiles.nushell.autoload = {
    "hostname".text = ''
use ../modules/hostname.nu *
use ../modules/machine-id.nu *
    '';
  };
}
