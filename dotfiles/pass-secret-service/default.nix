{ config, ... }:

{
  programs.password-store = {
    enable = true;
    settings.PASSWORD_STORE_DIR = "${config.home.homeDirectory}/.password-store";
  };

  services.pass-secret-service.enable = true;
}
