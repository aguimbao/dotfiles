{ pkgs, ... }:

let
  passBin = "${pkgs.proton-pass-cli}/bin/pass-cli";

  fragment = ''
    def __dotfiles_manifest_title [stem: string] {
      $"DOTFILES-MANIFEST-($stem)"
    }

    def __dotfiles_manifest_stem [] {
      ls ($env.DOTFILES_DIR | path join "hosts") | get name | path basename | str replace ".nix" "" | input list --fuzzy "Select host manifest:"
    }

    export def backup-manifest [] {
      let hostdir = ($env.DOTFILES_DIR | path join "hosts")
      for f in (ls $hostdir | get name | where {|p| $p ends-with ".nix" }) {
        let stem = ($f | path basename | str replace ".nix" "")
        let content = (open --raw $f)
        let existing = (try {
          ^${passBin} item view --vault-name dotfiles --item-title (__dotfiles_manifest_title $stem) --output json | from json
        } catch {
          null
        })
        if $existing == null {
          { title: (__dotfiles_manifest_title $stem), note: "", fields: [{ field_name: "CONTENT", field_type: "hidden", value: $content }] }
          | to json
          | ^${passBin} item create custom --vault-name dotfiles --from-template -
        } else {
          ^${passBin} item update --vault-name dotfiles --item-title (__dotfiles_manifest_title $stem) --field $"CONTENT=($content)"
        }
      }
    }

    export def setup-manifest [stem?: string] {
      let stem = (if ($stem | is-empty) { __dotfiles_manifest_stem } else { $stem })
      let content = (^${passBin} item view --vault-name dotfiles --item-title (__dotfiles_manifest_title $stem) --field CONTENT | str trim)
      $content | save --force ($env.DOTFILES_DIR | path join "hosts" $"($stem).nix")
    }
  '';
in
{
  dotfiles.nushell.modules = {
    "manifest".text = fragment;
  };

  dotfiles.nushell.autoload = {
    "manifest".text = ''
use ../modules/manifest.nu *
    '';
  };
}
