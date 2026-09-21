{ lib, pkgs, ... }:

let
  initFragment = ''
    export def __dotfiles_init_atuin [] {
      let suffix = (^${pkgs.openssl}/bin/openssl rand -hex 4 | str trim)
      let username = $"atuin-($suffix)"
      let email = $"($username)@local.invalid"
      let password = (^${pkgs.openssl}/bin/openssl rand -base64 24 | str trim)

      ^${pkgs.atuin}/bin/atuin register -u $username -e $email -p $password

      let key = (^${pkgs.atuin}/bin/atuin key | str trim)

      let existing = (try {
        ^${pkgs.proton-pass-cli}/bin/pass-cli item view --vault-name dotfiles --item-title 'ATUIN' --output json | from json
      } catch {
        null
      })

      if $existing == null {
        let template = {
          title: "ATUIN"
          note: ""
          fields: [
            { field_name: "USERNAME", field_type: "text", value: $username }
            { field_name: "EMAIL", field_type: "text", value: $email }
            { field_name: "PASSWORD", field_type: "hidden", value: $password }
            { field_name: "KEY", field_type: "hidden", value: $key }
          ]
        }

        $template | to json | ^${pkgs.proton-pass-cli}/bin/pass-cli item create custom --vault-name dotfiles --from-template -
      } else {
        ^${pkgs.proton-pass-cli}/bin/pass-cli item update \
          --vault-name dotfiles \
          --item-title ATUIN \
          --field $"USERNAME=($username)" \
          --field $"EMAIL=($email)" \
          --field $"PASSWORD=($password)" \
          --field $"KEY=($key)"
      }
    }
  '';
in
{
  dotfiles.nushell.alias.aliases."init-atuin" = "__dotfiles_init_atuin";

  dotfiles.nushell.modules = {
    "atuin-pass-cli".text = initFragment;
  };

  dotfiles.nushell.fragments = {
    initCommands = [ "__dotfiles_init_atuin" ];
  };
}
