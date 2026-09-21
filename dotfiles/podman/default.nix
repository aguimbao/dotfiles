{ config, lib, pkgs, ... }:

let
  yaml = pkgs.formats.yaml {};
in
{
  options.dotfiles.podman.containers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        image = lib.mkOption {
          type = lib.types.str;
          description = "Container image to run.";
        };
        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override the container entrypoint command.";
        };
        restart = lib.mkOption {
          type = lib.types.str;
          default = "no";
          description = "Container restart policy.";
        };
        usernsMode = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "User namespace mode (e.g. \"keep-id\").";
        };
        ports = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Host:container port mappings.";
        };
        volumes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Host:container volume mounts.";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Container environment variables.";
        };
        dataDir = lib.mkOption {
          type = lib.types.str;
          description = "Local data directory backing the container state.";
        };
      };
    }));
    default = { };
    description = "Podman compose containers. Each generates a docker-compose.yml at xdg.configHome/podman/<name>/ (fixed convention).";
  };

  config = {
    home.packages = [ pkgs.podman pkgs.podman-compose ];

    xdg.configFile = lib.mapAttrs' (name: c:
      lib.nameValuePair "podman/${name}/docker-compose.yml" {
        source = yaml.generate "podman-${name}-compose.yml" {
          services.${name} = lib.filterAttrs (_: v: v != null) {
            image = c.image;
            command = c.command;
            restart = c.restart;
            userns_mode = c.usernsMode;
            ports = c.ports;
            volumes = c.volumes;
            environment = c.environment;
          };
        };
      }
    ) config.dotfiles.podman.containers;
  };
}
