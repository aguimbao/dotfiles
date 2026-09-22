# Live-USB stage: minimal HM tooling in RAM (network, VPN, auth, fetch).
# Usage in minimal ISO: home-manager switch --flake $DOTFILES_DIR#nixos@live
{
  configuration-id = "live";
  home-manager-user = "nixos";
  system = "x86_64-linux";
  disabled = [
    # Live session runs from RAM: keep only install essentials
    # (git/gh/fnox/pass/vpn/tailscale/shell). Everything else arrives
    # with the real host.
    "steam"
    "discord"
    "qbittorrent"
    "vlc"
    "gimp"
    "godot"
    "unity-hub"
    "libreoffice"
    "element-desktop"
    "ungoogled-chromium"
    "flameshot"
    "kde-connect"
    "rustdesk"
    "scrcpy"
    "android-tools"
    "keymapp"
    "vicinae"
    "surrealist"
    "bruno"
    "powertop"
    "opensnitch"
    "syncthing"
    "tor"
    "sway"
    "atuin-server"
    "atuin"
    "ventoy"
    "disko"
    "impermanence"
    "proton-pass"
    "ghostty"
    "vscodium"
    "zellij"
    "neovim"
    "podman"
    "devcontainer"
    "opencode"
    "renovate"
    "jujutsu"
    "skim"
    "lazygit"
    "glances"
    "hyperfine"
    "yazi"
    "mutagen"
    "go"
    "rust"
    "nodejs"
    "bun"
    "python"
    "uv"
    "ffmpeg"
    "kubectl"
    "cloudflared"
    "fonts"
    "bluetooth"
    "carapace"
    "lfk"
    "hunk"
    "viu"
    "gping"
    "ast-grep"
    "dive"
    "jaq"
    "hexyl"
    "procs"
    "fish"
    "inshellisense"
    "cull"
    "ctx7"
    "plocate"
    "bubblewrap"
  ];
  params = {
    git.name = "Abraham";
    git.email = "abraham@aguimbao.me";
    git.signingKey = "key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuc9u4BwLvDoU3VCCE0WqDyy2ZFbx0e9OZvjExtfT/P abraham@aguimbao.me";
  };
  extraDirs = [ ];
}
