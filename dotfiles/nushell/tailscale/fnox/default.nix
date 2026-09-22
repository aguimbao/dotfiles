{
  dotfiles.fnox.profiles.tailscale.secrets = {
    TS_AUTHKEY = { provider = "protonpass"; value = "Dev/TAILSCALE/LINUX_AUTH_KEY"; };
  };

  dotfiles.nushell.modules = {
    "tailscale".text = ''
def "_ts login fnox" [...args] {
    use ./fnox.nu _fnox-run
    _fnox-run -p tailscale "sh" "-c" 'tailscale login --authkey="$TS_AUTHKEY" "$@"' "--" ...$args
}

export def --wrapped main [...args] {
    if (($args | first | default "") == "login") {
        _ts login fnox ...(if ($args | length) > 1 { $args | skip 1 } else { [] })
    } else {
        ^tailscale ...$args
    }
}

export def --wrapped ",ts" [...args] {
    main ...$args
}
    '';
  };

  dotfiles.nushell.autoload = {
    "tailscale".text = ''
use ../modules/tailscale.nu *
    '';
  };
}
