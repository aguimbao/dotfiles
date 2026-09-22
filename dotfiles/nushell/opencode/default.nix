{ ... }:

{
  dotfiles.nushell.modules = {
    "opencode".text = ''
export def --wrapped ",oc" [...args] {
    main ...$args
}

export def --wrapped ",oc s" [...args] {
    main --standalone ...$args
}

export def --wrapped main [...args] {
    use ./fnox.nu _fnox-run
    with-env {
        EDITOR: "code --wait"
    } {
        _fnox-run -p [omniroute github] opencode2 ...$args
    }
}

def "_oc strip-fences" [text?: string] {
    let input = (if $text != null { $text } else { $in })
    let trimmed = ($input | str trim)
    let lines = ($trimmed | lines)
    if ($lines | length) >= 2 and (($lines | first | str starts-with "```") and ($lines | last | str trim | str starts-with "```")) {
        $lines | skip 1 | drop 1 | str join (char newline) | str trim
    } else {
        $trimmed
    }
}

def "_oc sanitize-reference" [content: string] {
    $content
    | str replace --all "commits origin/($base)..HEAD (oneline)" "commits origin/($base)..HEAD \\(oneline\\)"
    | str replace --all "commits origin/($base)..HEAD (hash, subject, body)" "commits origin/($base)..HEAD \\(hash, subject, body\\)"
    | str replace --all "(no origin/($base) yet)" "\\(no origin/($base) yet\\)"
}

def "_oc expand-macros" [text: string] {
    mut res = $text

    let cat_matches = ($res | parse -r "!(?:`cat\\s+(?<p1>[^`]+)`|cat\\s+(?<p2>[^\\s`]+))")
    for row in $cat_matches {
        let raw_path = (if ($row.p1 | is-not-empty) { $row.p1 } else { $row.p2 } | str trim)
        let expanded_path = ($raw_path | path expand)
        if ($expanded_path | path exists) {
            let content = (_oc sanitize-reference (open --raw $expanded_path))
            let raw_pattern = (if ($row.p1 | is-not-empty) { $"!`cat ($row.p1)`" } else { $"!cat ($row.p2)" })
            $res = ($res | str replace $raw_pattern $content)
        }
    }

    let at_matches = ($res | parse -r "(?:^|\\s)@(?<p>[~./][^\\s]+)")
    for row in $at_matches {
        let raw_path = ($row.p | str trim)
        let expanded_path = ($raw_path | path expand)
        if ($expanded_path | path exists) {
            let content = (_oc sanitize-reference (open --raw $expanded_path))
            $res = ($res | str replace $"@($raw_path)" $content)
        }
    }

    $res
}

def "_oc resolve-cmd" [cmd: string, dir: path] {
    let candidates = [
        $cmd
        ($dir | path join ".opencode" "commands" $"($cmd).md")
        ($dir | path join ".opencode" "commands" $cmd)
        ($env.HOME | path join ".config" "opencode" "commands" $"($cmd).md")
        ($env.HOME | path join ".config" "opencode" "commands" $cmd)
    ]
    let found = ($candidates | where {|p| ($p | path exists) and (($p | path type) == "file") } | get -o 0)
    if $found == null {
        error make { msg: $"OpenCode command file '($cmd)' not found" }
    }
    $found
}

def "_oc strip-frontmatter" [text: string] {
    let trimmed = ($text | str trim)
    if ($trimmed | str starts-with "---") {
        let lines = ($trimmed | lines)
        let rest = ($lines | skip 1)
        let end_idx = ($rest | enumerate | where {|it| ($it.item | str trim) == "---" } | get -o 0.index)
        if $end_idx != null {
            $rest | skip ($end_idx + 1) | str join (char newline) | str trim
        } else {
            $trimmed
        }
    } else {
        $trimmed
    }
}

def "_oc run-one" [
    cmd: string
    dir: path
] {
    let dir = ($dir | path expand)
    let cmd_file = (_oc resolve-cmd $cmd $dir)
    let raw_prompt = (open --raw $cmd_file)
    let prompt = (_oc strip-frontmatter (_oc expand-macros $raw_prompt))

    let out = (
        do {
            cd $dir
            main run --title $cmd --agent shell-only $prompt
        }
        | complete
    )

    if $out.exit_code != 0 {
        error make { msg: $"opencode '($cmd)' failed: ($out.stderr | str trim)" }
    }

    let value = ($out.stdout | _oc strip-fences)

    if ($value | is-empty) {
        error make { msg: $"opencode '($cmd)' returned empty output" }
    }

    $value
}

export def ",oc branch-name" [
    dir: path
] {
    let raw = (_oc run-one generate-git-branch-name $dir)
    $raw
    | lines
    | where {|l| not ($l | str trim | is-empty) }
    | first
    | default ""
    | str replace --all "`" ""
    | str trim
}

export def ",oc commit-message" [
    dir: path
] {
    _oc run-one generate-git-commit-message $dir
}

export def ",oc pr-details" [
    dir: path
] {
    _oc run-one generate-gh-pr-details $dir
}
    '';
  };

  dotfiles.nushell.autoload = {
    "opencode".text = ''
use ../modules/opencode.nu *
    '';
  };

  dotfiles.fnox.profiles.omniroute.secrets = {};
}
