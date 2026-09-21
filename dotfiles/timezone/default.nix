{ config, lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "timezone" ] {
    value = "UTC";
  };
in
{
  options.dotfiles.timezone = lib.mkOption {
    type = lib.types.str;
    default = params.value;
    description = "System timezone";
  };

  config = lib.mkIf (options ? time) {
    time.timeZone = config.dotfiles.timezone;
  };
}
