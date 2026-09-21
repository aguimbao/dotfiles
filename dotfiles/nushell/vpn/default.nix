{ ... }:

{
  dotfiles.nushell.modules = {
    "vpn".text = ''
export def ",vpn on" [] {
    try {
        ^sudo resolvectl revert eth0
    } catch {
    }

    ^sudo wg-quick up wg0
}

export def ",vpn off" [] {
    try {
        ^sudo wg-quick down wg0
    } catch {
    }

    ^sudo resolvectl dns eth0 1.1.1.1
    ^sudo resolvectl domain eth0 '~.'
}
    ''
  };

  dotfiles.nushell.autoload = {
    "vpn".text = ''
use ../modules/vpn.nu *
    ''
  };
}
