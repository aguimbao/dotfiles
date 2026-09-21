{ config, pkgs, ... }:

{
  dotfiles.nushell.proton-drive.backups.pass-secret-service = {
    preSetup = "      __dotfiles_setup_pass_secret_service_key";
    preRestore = "        ^${pkgs.systemd}/bin/systemctl --user stop pass-secret-service";

    postSetup = ''
      let fingerprint = (__dotfiles_pass_secret_service_field GPG_FINGERPRINT)
      __dotfiles_validate_pass_secret_service_store "${config.home.homeDirectory}/.password-store" $fingerprint

      let encrypted = (glob "${config.home.homeDirectory}/.password-store/**/*.gpg")
      if ($encrypted | is-not-empty) {
        let passphrase = (__dotfiles_pass_secret_service_field GPG_PASSPHRASE)
        $passphrase | ^${pkgs.gnupg}/bin/gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --output /dev/null --decrypt ($encrypted | first)
      }

      ^${pkgs.systemd}/bin/systemctl --user restart pass-secret-service
    '';
  };
}
