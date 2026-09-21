{
  dotfiles.fnox.profiles.github.secrets = {
    GH_TOKEN = { provider = "protonpass"; value = "Dev/GITHUB/ADMIN_PAT"; };
    GITHUB_TOKEN = { provider = "protonpass"; value = "Dev/GITHUB/ADMIN_PAT"; };
  };

  dotfiles.nushell.modules = {
    "gh".text = ''
use ./fnox.nu _fnox-run

export def --wrapped gh [...args] {
  _fnox-run -p github gh ...$args
}
    '';
  };

  dotfiles.nushell.autoload = {
    "gh".text = ''
use ../modules/gh.nu *
    '';
  };
}
