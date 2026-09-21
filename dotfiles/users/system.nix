{ lib, manifest, homeManagerUser, options, ... }:

{
  config = lib.mkIf (options ? users.users) {
    users.mutableUsers = false;
    users.users.${homeManagerUser} = {
      isNormalUser = true;
      extraGroups = [ "networkmanager" "wheel" ];
      home = "/home/${homeManagerUser}";
    } // (lib.optionalAttrs (manifest ? "home-manager-user-password") {
      hashedPassword = manifest."home-manager-user-password";
    });

    users.users.root = lib.optionalAttrs (manifest ? "root-password") {
      hashedPassword = manifest."root-password";
    };
  };
}
