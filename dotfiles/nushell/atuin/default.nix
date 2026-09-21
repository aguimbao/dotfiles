{ ... }:

{
  # HM's atuin nushell integration writes into programs.nushell config,
  # which collides with our stitched ~/.config/nushell files.
  # Kept off until `atuin init nu` output is vendored as a module.
  # History still syncs via explicit `atuin sync` in backup hooks.
  programs.atuin.enableNushellIntegration = false;
}
