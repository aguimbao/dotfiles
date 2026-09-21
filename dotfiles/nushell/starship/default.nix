{ ... }:

{
  dotfiles.nushell.modules = {
    "starship-activate".text = ''
# Regenerate with: starship init nu | save -f ~/.config/nushell/modules/starship-activate.nu
# this file is both a valid
# - overlay which can be loaded with `overlay use starship.nu`
# - module which can be used with `use starship.nu`
# - script which can be used with `source starship.nu`
export-env { $env.STARSHIP_SHELL = "nu"; load-env {
    STARSHIP_SESSION_KEY: (random chars -l 16)
    PROMPT_MULTILINE_INDICATOR: (
        ^/home/aaa/.local/share/mise/installs/aqua-starship-starship/latest/.mise-bins/starship prompt --continuation
    )

    # Does not play well with default character module.
    # TODO: Also Use starship vi mode indicators?
    PROMPT_INDICATOR: ""

    PROMPT_COMMAND: {||
        (
            # The initial value of `$env.CMD_DURATION_MS` is always `0823`, which is an official setting.
            # See https://github.com/nushell/nushell/discussions/6402#discussioncomment-3466687.
            let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
            ^/home/aaa/.local/share/mise/installs/aqua-starship-starship/latest/.mise-bins/starship prompt
                --cmd-duration $cmd_duration
                $"--status=($env.LAST_EXIT_CODE)"
                --terminal-width (term size).columns
                ...(
                    if (which "job list" | where type == built-in | is-not-empty) {
                        ["--jobs", (job list | length)]
                    } else {
                        []
                    }
                )
        )
    }

    config: ($env.config? | default {} | merge {
        render_right_prompt_on_last_line: true
    })

    PROMPT_COMMAND_RIGHT: {||
        (
            # The initial value of `$env.CMD_DURATION_MS` is always `0823`, which is an official setting.
            # See https://github.com/nushell/nushell/discussions/6402#discussioncomment-3466687.
            let cmd_duration = if $env.CMD_DURATION_MS == "0823" { 0 } else { $env.CMD_DURATION_MS };
            ^/home/aaa/.local/share/mise/installs/aqua-starship-starship/latest/.mise-bins/starship prompt
                --right
                --cmd-duration $cmd_duration
                $"--status=($env.LAST_EXIT_CODE)"
                --terminal-width (term size).columns
                ...(
                    if (which "job list" | where type == built-in | is-not-empty) {
                        ["--jobs", (job list | length)]
                    } else {
                        []
                    }
                )
        )
    }
}}
    ''
  };

  dotfiles.nushell.autoload = {
    "starship".text = ''
use ../modules/starship-activate.nu *

try {
    if (which starship | is-not-empty) {
        job spawn {
            try {
                let config_dir = $nu.default-config-dir
                let regen_header = "# Regenerate with: starship init nu | save -f ~/.config/nushell/modules/starship-activate.nu\n"
                $regen_header + (^starship init nu)
                | save -f ($config_dir | path join "modules" "starship-activate.nu")
            }
        } | ignore
    }
}
    ''
  };
}
