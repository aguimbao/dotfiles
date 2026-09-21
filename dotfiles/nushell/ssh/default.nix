{ ... }:

{
  dotfiles.nushell.modules = {
    "ssh".text = ''
export-env {
    let ssh_agent_socket = ($env.XDG_RUNTIME_DIR? | default "/tmp" | path join "ssh-agent.socket")

    if ($env.SSH_CONNECTION? | is-empty) {
        $env.SSH_AUTH_SOCK = $ssh_agent_socket

        let agent_alive = if ($ssh_agent_socket | path exists) {
            (do { ^ssh-add -l } | complete).exit_code != 2
        } else {
            false
        }

        if not $agent_alive {
            rm -f $ssh_agent_socket
            ^ssh-agent -a $ssh_agent_socket | ignore
            mut retries = 0
            while not ($ssh_agent_socket | path exists) and $retries < 20 {
                sleep 10ms
                $retries = $retries + 1
            }
        }
    }
}
    ''
  };

  dotfiles.nushell.autoload = {
    "ssh".text = ''
use ../modules/ssh.nu *
    ''
  };
}
