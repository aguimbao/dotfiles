{ ... }:

{
  dotfiles.nushell.modules = {
    "devcontainer".text = ''
export def --wrapped ",dc up" [...args] {
    ^devcontainer up --docker-path podman --mount-git-worktree-common-dir ...$args
}

export def --wrapped ",dc down" [...args] {
    let workspace = ($args
        | parse --regex '^--workspace-folder=(?<path>.+)$'
        | get -o path.0
        | default $env.PWD
        | path expand)

    let ids = (
        ^podman ps --all --quiet
            --filter $"label=devcontainer.local_folder=($workspace)"
        | lines
        | where { |id| not ($id | is-empty) }
    )

    if not ($ids | is-empty) {
        ^podman rm --force ...$ids
    }
}
    '';
  };

  dotfiles.nushell.autoload = {
    "devcontainer".text = ''
use ../modules/devcontainer.nu *
    '';
  };
}
