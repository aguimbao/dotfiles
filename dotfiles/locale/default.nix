{ config, lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "locale" ] {
    value = "en_US.UTF-8";
  };
in
{
  options.dotfiles.locale = lib.mkOption {
    type = lib.types.str;
    default = params.value;
    description = "Default locale";
  };

  config = lib.mkIf (options ? i18n) {
    i18n.defaultLocale = config.dotfiles.locale;
  };
}
