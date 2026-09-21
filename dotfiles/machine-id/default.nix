{ lib, manifest, getParams, options, ... }:

let
  params = getParams [ "machine-id" ] { };
  value = params.value or null;
in
{
  options.dotfiles.machineId = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = value;
    description = "System machine-id, 32 lowercase hex (required: manifest.params.machine-id.value).";
  };

  assertions = lib.optionals (options ? systemd.machineId) [
    {
      assertion = value == null || builtins.match "[0-9a-f]{32}" value != null;
      message = "manifest.params.machine-id.value must be 32 lowercase hex characters";
    }
    {
      assertion = value != null;
      message = "manifest.params.machine-id.value is required (generate one with `new-machine-id`)";
    }
  ];

  config = lib.mkIf ((options ? systemd.machineId) && value != null) {
    systemd.machineId = value;
  };
}
