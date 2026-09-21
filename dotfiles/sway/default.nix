{ lib, options, ... }:

{
  config = lib.mkIf (options ? programs.sway) {
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
  };
}
