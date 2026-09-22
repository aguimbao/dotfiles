{ ... }:

{
  dotfiles.nushell.modules = {
    "git".text = ''
export def --wrapped ",g" [...args] {
    git ...$args
}

export def ",g repo-without-git-copy" [
    source_dir: path
] {
    let source_dir = ($source_dir | path expand)
    let destination_dir = $env.PWD

    let source_entries = (
        ls --all $source_dir
        | get name
        | where {|entry| ($entry | path basename) != ".git" }
    )

    let destination_entries = (
        ls --all $destination_dir
        | get name
        | where {|entry| ($entry | path basename) != ".git" }
    )

    $destination_entries | each {|entry|
        rm --recursive --force $entry
    }

    $source_entries | each {|entry|
        cp --recursive --force $entry $destination_dir
    }
}

export def "_wt worktrees root" [] {
    $env.HOME | path join "worktrees"
}

export def "_wt repo root" [] {
    git rev-parse --show-toplevel | str trim
}

export def "_wt repo id" [] {
    _wt repo root
    | str trim --left --char "/"
    | str replace --all "/" "__"
}

export def "_wt default branch" [] {
    let remote_head = (git symbolic-ref --quiet --short refs/remotes/origin/HEAD | str trim)
    $remote_head | str replace "origin/" ""
}

export def "_wt linked worktrees" [repo_root: path] {
    let common_dir = (git -C $repo_root rev-parse --path-format=absolute --git-common-dir | path dirname)
    git -C $repo_root worktree list --porcelain
    | split row "\n\n"
    | where {|block| not ($block | str trim | is-empty) }
    | each {|block|
        let lines = ($block | lines)
        let wt_path = ($lines | where {|l| $l starts-with "worktree "} | get -o 0 | default "" | str replace "worktree " "")
        let branch = ($lines | where {|l| $l starts-with "branch "} | get -o 0 | default "" | str replace "branch refs/heads/" "")
        { path: $wt_path, branch: $branch }
    }
    | where {|wt| $wt.path != $common_dir and not ($wt.path | is-empty) }
}

export def "_wt unescape newlines" [value?: string] {
    let input = (if $value != null { $value } else { $in })
    $input | str replace --all '\n' (char newline)
}

export def "_wt valid branch name" [value: string] {
    let v = ($value | str trim | str replace --all "`" "")
    (($v =~ '^[A-Za-z0-9._][A-Za-z0-9._/-]*$')
        and (not ($v =~ '\.\.|//|^/|/$')))
}

export def "_wt stage selection" [
    repo_root: path
    interactive_add: bool
] {
    if $interactive_add {
        let changed_files = (
            git -C $repo_root status --short
            | lines
            | each {|line|
                {
                    status: ($line | str substring 0..2 | str trim)
                    path: ($line | str substring 3.. | str trim)
                }
            }
        )

        if ($changed_files | is-empty) {
            error make {msg: "No changed files to stage"}
        }

        let selected_files = (
            $changed_files
            | each {|file| $"($file.status)  ($file.path)" }
            | input list --fuzzy --multi "Select files to stage"
            | each {|selection|
                $selection | str replace -r '^[A-Z? ]+\s+' ""
            }
        )

        if ($selected_files | is-empty) {
            error make {msg: "No files selected"}
        }

        $selected_files | each {|file|
            git -C $repo_root add -- $file
        }
    } else {
        git -C $repo_root add -A
    }
}

export def --env ",g wt-new" [] {
    let repo_root = (_wt repo root)
    let repo_id = (_wt repo id)
    let default_branch = (_wt default branch)
    let branch_name = (date now | format date "%Y%m%dT%H%M%SZ")

    let worktree_dir = (
        _wt worktrees root
        | path join $repo_id $branch_name
    )

    git -C $repo_root fetch origin

    mkdir ($worktree_dir | path dirname)
    git -C $repo_root worktree add --relative-paths -b $branch_name $worktree_dir $"origin/($default_branch)"

    cd $worktree_dir
}

export def ",g wt-delete" [
    --all (-a)
] {
    let repo_root = (_wt repo root)
    let worktrees = (_wt linked worktrees $repo_root)

    if ($worktrees | is-empty) {
        print "No worktrees to delete."
        return
    }

    let to_delete = (
        if $all {
            $worktrees
        } else {
            let choices = (
                $worktrees
                | each {|wt|
                    if ($wt.branch | is-empty) {
                        $wt.path
                    } else {
                        $"($wt.branch)  ($wt.path)"
                    }
                }
            )

            let selected = (
                $choices
                | input list --fuzzy --multi "Select worktrees to delete"
            )

            if ($selected | is-empty) {
                return
            }

            $worktrees
            | where {|wt|
                let label = (if ($wt.branch | is-empty) { $wt.path } else { $"($wt.branch)  ($wt.path)" })
                $label in $selected
            }
        }
    )

    $to_delete | each {|wt|
        try { git -C $repo_root worktree remove --force $wt.path }
    }

    git -C $repo_root worktree prune
}

export def --env ",g wt-cd" [worktree_name?: string] {
    let repo_root = (_wt repo root)
    let worktrees = (_wt linked worktrees $repo_root)

    if ($worktrees | is-empty) {
        print "No worktrees found."
        return
    }

    if ($worktree_name != null) {
        let match = (
            $worktrees
            | where {|wt|
                (($wt.branch == $worktree_name)
                    or (($wt.path | path basename) == $worktree_name)
                    or ($wt.path == $worktree_name))
            }
            | get -o 0
        )

        if ($match == null) {
            error make {msg: $"Worktree '($worktree_name)' not found"}
        }

        cd $match.path
        return
    }

    let choices = (
        $worktrees
        | each {|wt|
            if ($wt.branch | is-empty) {
                $wt.path
            } else {
                $"($wt.branch)  ($wt.path)"
            }
        }
    )

    let selected = (
        $choices
        | input list --fuzzy "Select worktree"
    )

    if ($selected | is-empty) {
        return
    }

    let target = (
        $worktrees
        | where {|wt|
            let label = (if ($wt.branch | is-empty) { $wt.path } else { $"($wt.branch)  ($wt.path)" })
            $label == $selected
        }
        | get -o 0
    )

    if ($target != null) {
        cd $target.path
    }
}

export def --env ",g wt-base-cd" [] {
    let gd = (do { git rev-parse --path-format=absolute --git-dir } | complete)
    let gcd = (do { git rev-parse --path-format=absolute --git-common-dir } | complete)

    if $gd.exit_code != 0 or $gcd.exit_code != 0 {
        error make { msg: "Not inside a git repository" }
    }

    let git_dir = ($gd.stdout | str trim | path expand)
    let common_dir = ($gcd.stdout | str trim | path expand)

    if $git_dir == $common_dir {
        error make { msg: "Not inside a worktree (already in base repository)" }
    }

    cd ($common_dir | path dirname)
}

export def ",g local-branch-delete" [
    --all (-a)
] {
    let repo_root = (_wt repo root)
    let default_branch = (_wt default branch)
    let branches = (
        git -C $repo_root branch --format="%(refname:short)|%(worktreepath)"
        | lines
        | where {|line| not ($line | str trim | is-empty) }
        | each {|line|
            let parts = ($line | split row "|")
            {
                name: ($parts | get 0)
                worktree: ($parts | get -o 1 | default "")
            }
        }
        | where {|b| $b.name != $default_branch and ($b.worktree | is-empty) }
    )

    if ($branches | is-empty) {
        print "No local branches to delete."
        return
    }

    let to_delete = (
        if $all {
            $branches.name
        } else {
            let selected = (
                $branches.name
                | input list --fuzzy --multi "Select branches to delete"
            )

            if ($selected | is-empty) {
                return
            }

            $selected
        }
    )

    $to_delete | each {|branch|
        try { git -C $repo_root branch -D $branch }
    }
}

export def ",g local-tag-delete" [
    --all (-a)
] {
    let repo_root = (_wt repo root)
    let tags = (
        git -C $repo_root tag --list
        | lines
        | where {|line| not ($line | str trim | is-empty) }
    )

    if ($tags | is-empty) {
        print "No local tags to delete."
        return
    }

    let to_delete = (
        if $all {
            $tags
        } else {
            let selected = (
                $tags
                | input list --fuzzy --multi "Select tags to delete"
            )

            if ($selected | is-empty) {
                return
            }

            $selected
        }
    )

    $to_delete | each {|tag|
        try { git -C $repo_root tag -d $tag }
    }
}

export def ",g local-prune" [] {
    ,g local-branch-delete --all
    ,g local-tag-delete --all
    ,g fetch --prune
}
    '';
  };

  dotfiles.nushell.autoload = {
    "git".text = ''
use ../modules/git.nu *
    '';
  };
}
