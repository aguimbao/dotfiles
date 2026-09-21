{ pkgs, ... }:

{
  home.packages = [ pkgs.gnupg ];

  programs.gpg.enable = true;

  services.gpg-agent = {
    enable = true;
    enableExtraSocket = true;
  };
}
