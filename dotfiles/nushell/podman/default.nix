{ ... }:

{
  dotfiles.nushell.modules = {
    "podman".text = ''
export def --wrapped ",pm" [...args] {
    podman ...$args
}

export def ",pm system-prune" [] {
    podman system prune -a --volumes -f

    let images = (podman image ls -a --filter dangling=true -q | lines)

    if not ($images | is-empty) {
        podman rmi -f ...$images
    }

    podman image prune --all --external --force
}

export def --env ",pm exec" [] {
    let connection_rows = (
        ^podman system connection list --format json
        | from json
    )

    let connections = [
        "local"
        ...($connection_rows | each {|row| $row.Name })
    ]

    let connection = (
        $connections
        | input list --fuzzy "Select Podman connection"
    )

    if ($connection | is-empty) {
        return
    }

    let container_rows = (
        if $connection == "local" {
            ^podman ps --format json | from json
        } else {
            ^podman --connection $connection ps --format json | from json
        }
    )

    let containers = [
        ...($container_rows | each {|row|
            let names = $row.Names

            if ($names | describe | str starts-with "list") {
                $names | first
            } else {
                $names
            }
        })
    ]

    if ($containers | is-empty) {
        print $"No running containers in: ($connection)"
        return
    }

    let container = (
        $containers
        | input list --fuzzy "Select running container"
    )

    if ($container | is-empty) {
        return
    }

    let shell = (
        ["/bin/bash" "/bin/sh" "bash" "sh"]
        | input list --fuzzy "Select shell"
    )

    if ($shell | is-empty) {
        return
    }

    if $connection == "local" {
        ^podman exec -it $container $shell
    } else {
        ^podman --connection $connection exec -it $container $shell
    }
}
    ''
  };

  dotfiles.nushell.autoload = {
    "podman".text = ''
use ../modules/podman.nu *
    ''
  };
}
