{ config, ... }:

let
  dataDir = "${config.xdg.dataHome}/atuin-server";
in
{
  dotfiles.podman.containers.atuin-server = {
    image = "ghcr.io/atuinsh/atuin:latest";
    command = "start";
    usernsMode = "keep-id";
    ports = [ "8888:8888" ];
    volumes = [ "${dataDir}/config:/config" ];
    environment = {
      ATUIN_HOST = "0.0.0.0";
      ATUIN_PORT = "8888";
      ATUIN_OPEN_REGISTRATION = "true";
      ATUIN_DB_URI = "sqlite:///config/atuin.db";
      RUST_LOG = "info,atuin_server=debug";
    };
    inherit dataDir;
  };
}
