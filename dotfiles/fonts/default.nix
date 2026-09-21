{ lib, pkgs, getParams, options, ... }:

let
  params = getParams [ "fonts" ] {
    enableFiraCode = true;
  };
in
{
  config = lib.mkIf (options ? fonts) {
    fonts.packages = lib.optionals params.enableFiraCode [
      pkgs.fira-code
      pkgs.nerd-fonts.fira-code
    ];
  };
}
