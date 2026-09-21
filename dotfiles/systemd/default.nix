{ config, lib, pkgs, ... }:

{
  options.dotfiles.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        description = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Unit description.";
        };
        type = lib.mkOption {
          type = lib.types.str;
          default = "simple";
          description = "Service type.";
        };
        workingDirectory = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Service working directory.";
        };
        pathPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Packages added to the service PATH environment.";
        };
        execStartPre = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Commands run before ExecStart.";
        };
        execStart = lib.mkOption {
          type = lib.types.str;
          description = "Main service command.";
        };
        execStop = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Stop command (null omits ExecStop).";
        };
        timeoutStartSec = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Start timeout in seconds (null omits it, 0 disables).";
        };
      };
    }));
    default = { };
    description = "User systemd services. Renders to systemd.user.services.<name> with shared boilerplate (PATH from pathPackages, etc.).";
  };

  config = {
    systemd.user.services = lib.mapAttrs (name: svc: {
      Unit = { Description = svc.description; };
      Service = { Type = svc.type; ExecStart = svc.execStart; }
        // (lib.optionalAttrs (svc.workingDirectory != null) { WorkingDirectory = svc.workingDirectory; })
        // (lib.optionalAttrs (svc.pathPackages != [ ]) { Environment = [ "PATH=${pkgs.lib.makeBinPath svc.pathPackages}" ]; })
        // (lib.optionalAttrs (svc.execStartPre != [ ]) { ExecStartPre = svc.execStartPre; })
        // (lib.optionalAttrs (svc.execStop != null) { ExecStop = svc.execStop; })
        // (lib.optionalAttrs (svc.timeoutStartSec != null) { TimeoutStartSec = svc.timeoutStartSec; });
    }) config.dotfiles.systemd.services;
  };
}
