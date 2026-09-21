{ config, pkgs, ... }:

let
  containerName = "atuin-server";
  composeDir = "${config.xdg.configHome}/podman/${containerName}";
  container = config.dotfiles.podman.containers.${containerName};
in
{
  dotfiles.systemd.services.atuin-server = {
    description = "Atuin sync server";
    workingDirectory = composeDir;
    pathPackages = [ pkgs.podman pkgs.podman-compose ];
    execStartPre = [
      "mkdir -p ${container.dataDir}/config"
      "${pkgs.podman}/bin/podman pull ${container.image}"
    ];
    execStart = "${pkgs.podman-compose}/bin/podman-compose -f ${composeDir}/docker-compose.yml -p atuin-server up";
    execStop = "${pkgs.podman-compose}/bin/podman-compose -f ${composeDir}/docker-compose.yml -p atuin-server down";
    timeoutStartSec = 0;
  };
}
