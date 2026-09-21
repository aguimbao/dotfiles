{ config, pkgs, ... }:

let
  store = "${config.home.homeDirectory}/.password-store";
  itemTitle = "PASS-SECRET-SERVICE";

  fragment = ''
    export def __dotfiles_pass_secret_service_field [field: string] {
      (
        ^${pkgs.proton-pass-cli}/bin/pass-cli item view
        --vault-name dotfiles
        --item-title "${itemTitle}"
        --field $field
      ) | str trim
    }

    export def __dotfiles_pass_secret_service_key_fingerprint [private_key: string] {
      let output = (
        $private_key
        | ^${pkgs.gnupg}/bin/gpg --batch --with-colons --import-options show-only --import
      )
      $output
      | lines
      | where {|line| $line starts-with "fpr:" }
      | first
      | split row ":"
      | get 9
    }

    export def __dotfiles_validate_pass_secret_service_store [store: string, fingerprint: string] {
      let gpg_id = $"($store)/.gpg-id"
      if not ($gpg_id | path exists) {
        error make { msg: $"Password store is missing ($gpg_id)" }
      }

      let recipients = (open --raw $gpg_id | lines | each {|line| $line | str trim } | where {|line| not ($line | is-empty) })
      if $recipients != [$fingerprint] {
        error make { msg: $"Password store recipients do not match PASS-SECRET-SERVICE: ($recipients | str join ', ')" }
      }
    }

    export def __dotfiles_setup_pass_secret_service_key [] {
      let fingerprint = (__dotfiles_pass_secret_service_field GPG_FINGERPRINT)
      let private_key = (__dotfiles_pass_secret_service_field GPG_PRIVATE_KEY)
      let ownertrust = (__dotfiles_pass_secret_service_field GPG_OWNERTRUST)
      let revocation_certificate = (__dotfiles_pass_secret_service_field GPG_REVOCATION_CERTIFICATE)

      let exported_fingerprint = (__dotfiles_pass_secret_service_key_fingerprint $private_key)
      if $exported_fingerprint != $fingerprint {
        error make { msg: $"PASS-SECRET-SERVICE fingerprint mismatch: expected ($fingerprint), got ($exported_fingerprint)" }
      }

      $private_key | ^${pkgs.gnupg}/bin/gpg --batch --import
      $"($ownertrust)\n" | ^${pkgs.gnupg}/bin/gpg --batch --import-ownertrust

      let revocation_dir = "${config.home.homeDirectory}/.gnupg/openpgp-revocs.d"
      let revocation_file = $"($revocation_dir)/($fingerprint).rev"
      mkdir $revocation_dir
      $revocation_certificate | save --force $revocation_file
      ^${pkgs.coreutils}/bin/chmod 600 $revocation_file

      let secret_key = (do {
        ^${pkgs.gnupg}/bin/gpg --batch --list-secret-keys $fingerprint
      } | complete)
      if $secret_key.exit_code != 0 {
        error make { msg: $"Failed to import PASS-SECRET-SERVICE secret key ($fingerprint)" }
      }

      if not ("${store}/.gpg-id" | path exists) {
        if ("${store}" | path exists) and ((ls --all "${store}" | is-not-empty)) {
          error make { msg: "Refusing to initialize non-empty password store without .gpg-id" }
        }
        with-env { PASSWORD_STORE_DIR: "${store}" } {
          ^${pkgs.pass}/bin/pass init $fingerprint
        }
      }
      __dotfiles_validate_pass_secret_service_store "${store}" $fingerprint
    }

    export def __dotfiles_init_pass_secret_service [] {
      let existing = (do {
        ^${pkgs.proton-pass-cli}/bin/pass-cli item view --vault-name dotfiles --item-title "${itemTitle}" --output json
      } | complete)

      if $existing.exit_code == 0 {
        let fingerprint = (__dotfiles_pass_secret_service_field GPG_FINGERPRINT)
        let local_gpg_id = "${store}/.gpg-id"
        if not ($local_gpg_id | path exists) {
          error make { msg: "PASS-SECRET-SERVICE already exists in Proton Pass; run setup-pass-secret-service" }
        }
        __dotfiles_validate_pass_secret_service_store "${store}" $fingerprint

        let secret_key = (do {
          ^${pkgs.gnupg}/bin/gpg --batch --list-secret-keys $fingerprint
        } | complete)
        if $secret_key.exit_code != 0 {
          error make { msg: "PASS-SECRET-SERVICE exists but its local GPG key is missing; run setup-pass-secret-service" }
        }

        print "PASS-SECRET-SERVICE is already initialized"
        return
      }

      if ("${store}/.gpg-id" | path exists) {
        error make { msg: "Local password store is already initialized but PASS-SECRET-SERVICE is missing from Proton Pass" }
      }
      if ("${store}" | path exists) and ((ls --all "${store}" | is-not-empty)) {
        error make { msg: "Refusing to initialize non-empty password store without .gpg-id" }
      }

      let tmp = (^${pkgs.coreutils}/bin/mktemp -d | str trim)
      let gnupg_home = $"($tmp)/gnupg"
      mkdir $gnupg_home
      ^${pkgs.coreutils}/bin/chmod 700 $gnupg_home

      try {
        let passphrase = (^${pkgs.openssl}/bin/openssl rand -base64 48 | str trim)
        let user_id = "Pass Secret Service <pass-secret-service@local.invalid>"

        $passphrase | with-env { GNUPGHOME: $gnupg_home } {
          ^${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key $user_id future-default cert never
        }

        let key_listing = (with-env { GNUPGHOME: $gnupg_home } {
          ^${pkgs.gnupg}/bin/gpg --batch --with-colons --list-secret-keys $user_id
        })
        let fingerprint = (
          $key_listing
          | lines
          | where {|line| $line starts-with "fpr:" }
          | first
          | split row ":"
          | get 9
        )

        $passphrase | with-env { GNUPGHOME: $gnupg_home } {
          ^${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-add-key $fingerprint future-default encr never
        }

        let private_key = (
          $passphrase | with-env { GNUPGHOME: $gnupg_home } {
            ^${pkgs.gnupg}/bin/gpg --batch --pinentry-mode loopback --passphrase-fd 0 --armor --export-options backup,mode1003 --export-secret-keys $fingerprint
          }
        )
        let ownertrust = $"($fingerprint):6:"
        let revocation_certificate = (open --raw $"($gnupg_home)/openpgp-revocs.d/($fingerprint).rev")

        let template = {
          title: "${itemTitle}"
          fields: [
            { field_name: "GPG_FINGERPRINT", field_type: "text", value: $fingerprint }
            { field_name: "GPG_PRIVATE_KEY", field_type: "hidden", value: $private_key }
            { field_name: "GPG_OWNERTRUST", field_type: "hidden", value: $ownertrust }
            { field_name: "GPG_PASSPHRASE", field_type: "hidden", value: $passphrase }
            { field_name: "GPG_REVOCATION_CERTIFICATE", field_type: "hidden", value: $revocation_certificate }
          ]
        }

        $template | to json | ^${pkgs.proton-pass-cli}/bin/pass-cli item create custom --vault-name dotfiles --from-template -

        $private_key | ^${pkgs.gnupg}/bin/gpg --batch --import
        $"($ownertrust)\n" | ^${pkgs.gnupg}/bin/gpg --batch --import-ownertrust
        with-env { PASSWORD_STORE_DIR: "${store}" } {
          ^${pkgs.pass}/bin/pass init $fingerprint
        }
        ^${pkgs.systemd}/bin/systemctl --user restart pass-secret-service
      } finally {
        rm -rf $tmp
      }
    }
  '';
in
{
  dotfiles.nushell.alias.aliases."init-pass-secret-service" = "__dotfiles_init_pass_secret_service";

  dotfiles.nushell.modules = {
    "pass-secret-service".text = fragment;
  };

  dotfiles.nushell.fragments = {
    initCommands = [ "__dotfiles_init_pass_secret_service" ];
  };
}
