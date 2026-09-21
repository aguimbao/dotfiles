{ config, lib, ... }:

{
  config = lib.mkIf (config.programs.atuin.enable or false) {
    programs.atuin.settings.sync_address = "http://localhost:8888";
  };
}
