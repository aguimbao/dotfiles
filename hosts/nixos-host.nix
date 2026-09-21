# Real-host manifest. Contains sensitive values (password hashes, IDs).
# Back it up with `backup-manifest`, restore with `setup-manifest <id>`.
# Only hosts/live.nix is pre-made in the repo (nothing installed yet at
# live-USB time to fetch anything with).
{
  configuration-id = "nixos-host";
  home-manager-user = "alice";
  system = "x86_64-linux";
  disabled = [ ];
  params = {
    # Generate values with `new-hostname` / `new-machine-id`, paste here.
    # hostname.value = "HOSTNAME-XXXX";
    # machine-id.value = "0123456789abcdef0123456789abcdef";
    # git identity (required, differs per host):
    # git.name = "Abraham";
    # git.email = "abraham@aguimbao.me";
    # git.signingKey = "key::ssh-ed25519 AAAA... user@host";
    # disko.device = "/dev/vda";
  };
  # Password hashes (sha512crypt `$6$...`, immutable users).
  # Generate with `mkpasswd -m sha512crypt`, back up via `backup-manifest`.
  # home-manager-user-password = "$6$...";
  # root-password = "$6$...";
  extraDirs = [ ];
}
