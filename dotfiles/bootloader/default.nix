{ lib, options, ... }:

{
  config = lib.mkIf (options ? boot.loader) {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
