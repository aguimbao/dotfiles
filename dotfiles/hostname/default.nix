{ config, lib, manifest, getParams, options, ... }:

let
  params = getParams [ "hostname" ] { };
  value = params.value or null;
in
{
  options.dotfiles.hostname = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = value;
    description = "System hostname (required: manifest.params.hostname.value).";
  };

  assertions = lib.optionals (options ? networking) [
    {
      assertion = value != null;
      message = "manifest.params.hostname.value is required (generate one with `new-hostname`)";
    }
  ];

  config = lib.mkIf ((options ? networking) && value != null) {
    networking.hostName = value;
  };
}
