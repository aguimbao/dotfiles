{ config, lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "keyboard-layout" ] {
    value = "us";
    compose = "lalt";
  };
in
{
  options.dotfiles.keyboardLayout = lib.mkOption {
    type = lib.types.str;
    default = params.value;
    description = "Keyboard layout";
  };

  options.dotfiles.composeKey = lib.mkOption {
    type = lib.types.str;
    default = params.compose;
    description = "XKB compose key";
  };

  config = lib.mkIf (options ? services.xserver) {
    services.xserver.xkb = {
      layout = config.dotfiles.keyboardLayout;
      options = "compose:${config.dotfiles.composeKey}";
    };
  };
}
