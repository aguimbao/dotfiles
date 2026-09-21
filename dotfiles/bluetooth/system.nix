{ lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "bluetooth" ] {
    experimental = true;
    kernelExperimental = true;
  };
in
{
  config = lib.mkIf (options ? hardware.bluetooth) {
    hardware.bluetooth = {
      enable = true;
      settings.Policy.AutoEnable = true;
      settings.General = {
        Experimental = params.experimental;
        KernelExperimental = params.kernelExperimental;
      };
    };
    services.blueman.enable = true;
  };
}
