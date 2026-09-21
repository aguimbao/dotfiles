{ ... }:

{
  dotfiles.nushell.modules = {
  };

  dotfiles.nushell.autoload = {
    "nushell".text = ''
$env.config.show_banner = false
    '';
  };

  dotfiles.nushell.envExtra = [
    ''
      $env.TELEMETRY_ENABLED = "false"
      $env.CODEGRAPH_TELEMETRY = "0"
      $env.EDITOR = "codium --wait"
      $env.VISUAL = "codium --wait"
    ''
  ];
}
