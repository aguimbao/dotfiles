{ config, lib, homeManagerUser, ... }:

let
  cfg = config.dotfiles.activation-scripts.scripts;

  activationEntries = builtins.listToAttrs (map
    (name: lib.nameValuePair "dotfiles-${name}" cfg.${name})
    (builtins.attrNames cfg));
in
{
  options.dotfiles.activation-scripts.scripts = lib.mkOption {
    type = lib.types.attrsOf lib.types.lines;
    default = {};
    internal = true;
    description = "Activation scripts keyed by name. Body is run as-is by Home Manager.";
  };

  config = {
    home-manager.users.${homeManagerUser}.home.activation = activationEntries;
  };
}
