{ lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "disko" ] {
    device = "/dev/vda";
    nixSize = "40G";
  };
in
{
  config = lib.mkIf (options ? disko.devices) {
    disko.devices = {
      disk.main = {
        type = "disk";
        device = params.device;
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings = {
                  allowDiscards = true;
                };
                content = {
                  type = "lvm_pv";
                  vg = "pool";
                };
              };
            };
          };
        };
      };
      lvm_vg.pool = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = "8G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };
          nix = {
            size = params.nixSize;
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
            };
          };
          persist = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/persist";
            };
          };
        };
      };
    };
  };
}
