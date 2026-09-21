{ lib, options, ... }:

let
  persistDir = "/persist";
in
{
  config = lib.mkIf (options ? environment.persistence) {
    boot.tmp.useTmpfs = true;
    boot.initrd.systemd.enable = true;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "defaults" "size=8G" "mode=755" ];
    };
    environment.persistence."${persistDir}" = {
      hideMounts = true;
      directories = [];
      files = [];
    };
  };
}
