{ ... }:

{
  dotfiles.nushell.modules = {
    "git-gh".text = ''
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

export def "_g-gh-oc parse args" [args: list<string>] {
    mut help = false
    mut ai = false
    mut branch = false
    mut branch_val = ""
    mut add = false
    mut commit = false
    mut commit_val = ""
    mut push = false
    mut pr = false
    mut pr_val = ""
    mut interactive = false
    mut auto_merge = false
    mut wait_pr = false
    mut restore_branch = false
    mut prune_local = false
    mut final_pull = false

    mut i = 0
    let len = ($args | length)
    while $i < $len {
        let arg = ($args | get $i)
        match $arg {
            "--help" | "-h" => { $help = true; $i += 1 }
            "--" => { $i += 1 }
            "--ai" => { $ai = true; $i += 1 }
            "--interactive-add" | "-i" => { $interactive = true; $i += 1 }
            "--auto-merge" | "-a" => { $auto_merge = true; $i += 1 }
            "--push" | "-p" => { $push = true; $i += 1 }
            "--wait-pr" => { $wait_pr = true; $i += 1 }
            "--restore-branch" => { $restore_branch = true; $i += 1 }
            "--prune-local" => { $prune_local = true; $i += 1 }
            "--final-pull" => { $final_pull = true; $i += 1 }
            "--branch" | "-b" => {
                $branch = true
                $i += 1
                if $i < $len and not (($args | get $i) starts-with "-") {
                    $branch_val = ($args | get $i)
                    $i += 1
                }
            }
            "--add" => {
                $add = true
                $i += 1
            }
            "--commit" | "-c" => {
                $commit = true
                $i += 1
                if $i < $len and not (($args | get $i) starts-with "-") {
                    $commit_val = ($args | get $i)
                    $i += 1
                }
            }
            "--pr" => {
                $pr = true
                $i += 1
                if $i < $len and not (($args | get $i) starts-with "-") {
                    $pr_val = ($args | get $i)
                    $i += 1
                }
            }
            _ => {
                error make { msg: $"Unknown argument: ($arg)" }
            }
        }
    }

    if $help {
        print "Usage: ,g-gh-oc full-flow [flags]

Flags:
  --ai                     Use opencode for branch name, commit message, PR details
  --interactive-add, -i    Interactively choose files to stage
  --auto-merge, -a         Enable GitHub auto-merge on the PR
  --push, -p               Push current branch to origin
  --wait-pr                Wait for CI checks and auto-merge PR
  --restore-branch         Checkout initial branch at end (requires --branch)
  --prune-local            Run ,g local-prune at end
  --final-pull             Run git pull at end
  --branch, -b <name>      Create branch (or omit name if --ai)
  --add                    Stage changed files
  --commit, -c <msg>       Commit staged files (or omit msg if --ai)
  --pr <title>             Create pull request (or omit title if --ai)
  --help, -h               Show this help message"
        return { help: true }
    }

    if $branch and (not $ai) and ($branch_val | str trim | is-empty) {
        error make { msg: "--branch requires a branch name when --ai is not used" }
    }

    if $commit and (not $ai) and ($commit_val | str trim | is-empty) {
        error make { msg: "--commit requires a commit message when --ai is not used" }
    }

    if $pr and (not $ai) and ($pr_val | str trim | is-empty) {
        error make { msg: "--pr requires a PR title when --ai is not used" }
    }

    if $wait_pr and (not $pr) {
        error make { msg: "--wait-pr requires --pr" }
    }

    if $restore_branch and (not $branch) {
        error make { msg: "--restore-branch requires --branch" }
    }

    {
        help: false
        ai: $ai
        branch: $branch
        branch_val: $branch_val
        add: $add
        commit: $commit
        commit_val: $commit_val
        push: $push
        pr: $pr
        pr_val: $pr_val
        interactive: $interactive
        auto_merge: $auto_merge
        wait_pr: $wait_pr
        restore_branch: $restore_branch
        prune_local: $prune_local
        final_pull: $final_pull
    }
}

# Orchestrate full git & GitHub workflow (branch, stage, commit, push, PR, merge, restore, prune, pull)
export def --wrapped ",g-gh-oc full-flow" [...args] {
    use ./opencode.nu [",oc branch-name", ",oc commit-message", ",oc pr-details"]
    use ./gh-wrap.nu gh
    let parsed = (_g-gh-oc parse args $args)

    if ($parsed.help | default false) {
        return
    }

    let repo_root = (_wt repo root)
    let default_branch = (_wt default branch)

    if not ($parsed.branch or $parsed.add or $parsed.commit or $parsed.push or $parsed.pr) {
        print "No actions specified. Use --branch, --add, --commit, --push, and/or --pr."
        return
    }

    let initial_branch = (git -C $repo_root branch --show-current | str trim)

    if $parsed.branch {
        let branch_name = (
            if $parsed.ai {
                let name = (,oc branch-name $repo_root)
                if not (_wt valid branch name $name) {
                    error make { msg: $"Invalid branch name from opencode: ($name)" }
                }
                $name
            } else {
                $parsed.branch_val
            }
        )

        let current = (git -C $repo_root branch --show-current | str trim)
        if ($current == $default_branch or ($current | is-empty)) {
            git -C $repo_root checkout -b $branch_name
        } else if $current != $branch_name {
            git -C $repo_root branch -m $branch_name
        }
    }

    if $parsed.add {
        _wt stage selection $repo_root $parsed.interactive
    }

    if $parsed.commit {
        let commit_message = (
            if $parsed.ai {
                let msg = (,oc commit-message $repo_root | _wt unescape newlines)
                if ($msg | str trim | is-empty) {
                    error make { msg: "Empty commit message from opencode" }
                }
                $msg
            } else {
                _wt unescape newlines $parsed.commit_val
            }
        )

        let parts = (
            $commit_message
            | split row -r '\r?\n\s*\r?\n'
            | each {|p| $p | str trim }
            | where {|p| not ($p | is-empty) }
        )
        let commit_title = ($parts | get -o 0 | default ($commit_message | str trim))
        let commit_body = (if ($parts | length) > 1 { $parts | skip 1 | str join "\n\n" } else { "" })

        if ($commit_body | is-empty) {
            git -C $repo_root commit -m $commit_title
        } else {
            git -C $repo_root commit -m $commit_title -m $commit_body
        }
    }

    if $parsed.push {
        let current = (git -C $repo_root branch --show-current | str trim)
        if ($current | is-empty) {
            error make { msg: "Detached HEAD, cannot push" }
        }
        git -C $repo_root push --set-upstream origin $current
    }

    mut pr_url = ""
    if $parsed.pr {
        let current = (git -C $repo_root branch --show-current | str trim)
        if ($current | is-empty) {
            error make { msg: "Detached HEAD, cannot create PR" }
        }

        let pr_raw = (
            if $parsed.ai {
                ,oc pr-details $repo_root
            } else {
                $parsed.pr_val
            }
        )

        let unescaped = (_wt unescape newlines $pr_raw | str trim)
        let lines = ($unescaped | lines)
        let pr_name = ($lines | get -o 0 | default "" | str trim | str replace --all "`" "")
        let pr_description = (
            if ($lines | length) > 1 {
                $lines | skip 1 | str join (char newline) | str trim
            } else {
                ""
            }
        )

        if ($pr_name | is-empty) {
            error make { msg: "Empty PR title" }
        }

        $pr_url = (
            gh pr create
                --base $default_branch
                --head $current
                --title $pr_name
                --body $pr_description
            | str trim
        )

        if $parsed.auto_merge {
            gh pr merge $pr_url --auto --squash
        }
    }

    if $parsed.wait_pr {
        let merge_recap = (,g-gh prs-auto-merge --pr $pr_url --fix-behind-rebase --fix-conflict --fix-ci)
        let is_merged = ($merge_recap | any {|r| $r.result == "Merged" })
        if not $is_merged {
            print $"PR ($pr_url) was not merged. Aborting subsequent steps."
            return $pr_url
        }
    }

    if $parsed.restore_branch and $parsed.branch {
        if ($initial_branch | is-not-empty) {
            let current = (git -C $repo_root branch --show-current | str trim)
            if $current != $initial_branch {
                let branch_exists = (do { git -C $repo_root show-ref --verify --quiet $"refs/heads/($initial_branch)" } | complete).exit_code == 0
                if $branch_exists {
                    git -C $repo_root checkout $initial_branch
                } else {
                    print $"Cannot restore initial branch '($initial_branch)': branch does not exist."
                }
            }
        }
    }

    if $parsed.prune_local {
        ,g local-prune
    }

    if $parsed.final_pull {
        git -C $repo_root pull
    }

    if ($pr_url | is-not-empty) {
        $pr_url
    }
}

export def "_pr_has_failed_checks" [checks?: any] {
    let list = ($checks | default [])
    if ($list | is-empty) {
        return false
    }
    ($list | any {|c|
        let conclusion = ($c | get -o conclusion | default "")
        let state = ($c | get -o state | default "")
        (($conclusion in ["FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "CANCELLED"]) or ($state in ["FAILURE", "ERROR"]))
    })
}

export def "_pr_has_running_checks" [checks?: any] {
    let list = ($checks | default [])
    if ($list | is-empty) {
        return false
    }
    ($list | any {|c|
        let st = ($c | get -o status | default "")
        let state = ($c | get -o state | default "")
        let conc = ($c | get -o conclusion | default "")
        (($st in ["IN_PROGRESS", "QUEUED", "WAITING", "PENDING"]) or ($state in ["PENDING", "EXPECTED"]) or ($st != "COMPLETED" and ($conc | is-empty)))
    })
}

export def "_pr_resolve_rebase_conflicts" [work_dir: path] {
    loop {
        let is_rebasing = (
            (($work_dir | path join ".git" "rebase-merge" | path exists)
            or ($work_dir | path join ".git" "rebase-apply" | path exists))
        )
        if not $is_rebasing {
            return "resolved"
        }

        let unmerged = (
            git -C $work_dir diff --name-only --diff-filter=U
            | lines
            | each {|l| $l | str trim }
            | where {|l| not ($l | is-empty) }
        )

        if ($unmerged | is-not-empty) {
            print $"Found ($unmerged | length) conflicted files:"
            for file in $unmerged {
                print $"  - ($file)"
            }

            for file in $unmerged {
                let full_path = ($work_dir | path join $file)

                let diff_output = (do { git -C $work_dir diff --color=always -- $file } | complete)
                if $diff_output.exit_code == 0 and not ($diff_output.stdout | is-empty) {
                    let diff_lines = ($diff_output.stdout | lines)
                    print $"\n--- Conflict preview: ($file) ---"
                    let max_lines = 40
                    if ($diff_lines | length) > $max_lines {
                        $diff_lines | take $max_lines | each {|l| print $l }
                        let remaining = (($diff_lines | length) - $max_lines)
                        print $"--- [truncated, ($remaining) lines remaining] ---"
                    } else {
                        $diff_lines | each {|l| print $l }
                    }
                    print "---------------------------------\n"
                }

                let choice = ([
                    "Keep current"
                    "Keep incoming"
                    "Keep both"
                    "Open editor"
                    "Abort and skip PR"
                ] | input list $"Resolution for ($file):")

                match $choice {
                    "Keep current" => {
                        try { git -C $work_dir checkout --ours -- $file }
                        try { git -C $work_dir add -A -- $file }
                    }
                    "Keep incoming" => {
                        try { git -C $work_dir checkout --theirs -- $file }
                        try { git -C $work_dir add -A -- $file }
                    }
                    "Keep both" => {
                        if ($full_path | path exists) {
                            let text = (open --raw $full_path | lines | where {|l| not ($l =~ "^(<<<<<<<|=======|>>>>>>>)") } | str join (char newline))
                            $"($text)\n" | save -f $full_path
                        }
                        try { git -C $work_dir add -A -- $file }
                    }
                    "Open editor" => {
                        let editor = ($env.VISUAL? | default ($env.EDITOR? | default "code --wait"))
                        let parts = ($editor | split row " ")
                        let exe = ($parts | get 0)
                        let args = ($parts | skip 1)
                        print $"Opening ($file) in ($editor)..."
                        ^$exe ...$args $full_path
                        if ($full_path | path exists) {
                            let has_markers = (open --raw $full_path | lines | any {|l| $l =~ "^(<<<<<<<|=======|>>>>>>>)" })
                            if $has_markers {
                                print $"Warning: ($file) still contains conflict markers!"
                            }
                        }
                        try { git -C $work_dir add -A -- $file }
                    }
                    _ => {
                        print "Conflict resolution aborted by user."
                        try { git -C $work_dir rebase --abort }
                        return "aborted"
                    }
                }
            }
        }

        let cont_res = (with-env { GIT_EDITOR: "true" } {
            do { git -C $work_dir rebase --continue } | complete
        })

        if $cont_res.exit_code == 0 {
            continue
        }

        let check_unmerged = (
            git -C $work_dir diff --name-only --diff-filter=U
            | lines
            | where {|l| not ($l | str trim | is-empty) }
        )
        if ($check_unmerged | is-empty) {
            let skip_res = (do { git -C $work_dir rebase --skip } | complete)
            if $skip_res.exit_code != 0 {
                try { git -C $work_dir rebase --abort }
                return "failed"
            }
        }
    }
}

export def "_pr_rerun_failed_ci" [pr_number: int, head_sha: string, status_checks: any] {
    use ./gh-wrap.nu gh
    let checks = ($status_checks | default [])

    let check_run_ids = (
        $checks
        | where {|c|
            let conclusion = ($c | get -o conclusion | default "")
            let state = ($c | get -o state | default "")
            (($conclusion in ["FAILURE", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE", "CANCELLED"]) or ($state in ["FAILURE", "ERROR"]))
        }
        | each {|c|
            let url = ($c | get -o detailsUrl | default "")
            if ($url =~ '/actions/runs/\d+') {
                $url | parse -r '/actions/runs/(?<id>\d+)' | get -o 0.id
            } else {
                null
            }
        }
        | where {|id| $id != null and not ($id | is-empty) }
    )

    let commit_runs_res = (do {
        gh run list --commit $head_sha --json "databaseId,conclusion,status"
    } | complete)

    let commit_run_ids = (
        if $commit_runs_res.exit_code == 0 {
            $commit_runs_res.stdout
            | from json
            | where {|r|
                let conc = ($r.conclusion | default "")
                $conc in ["failure", "timed_out", "action_required", "startup_failure", "cancelled"]
            }
            | get -o databaseId
            | default []
            | each {|id| $id | into string }
        } else {
            []
        }
    )

    let run_ids = ($check_run_ids | append $commit_run_ids | uniq)

    if ($run_ids | is-empty) {
        print $"No rerun-able GitHub Action runs found for PR #($pr_number)."
        return false
    }

    mut triggered = false
    for run_id in $run_ids {
        print $"Rerunning failed jobs in workflow run #($run_id)..."
        let rerun_res = (do { gh run rerun $run_id --failed } | complete)
        if $rerun_res.exit_code == 0 {
            $triggered = true
        } else {
            print $"Failed to trigger rerun for run #($run_id): ($rerun_res.stderr | str trim)"
        }
    }

    $triggered
}

export def ",g-gh prs-auto-merge" [
    --all (-a)
    --fix-behind-rebase
    --fix-conflict
    --fix-ci
    --pr (-p): any
] {
    use ./gh-wrap.nu gh
    let repo_root = (_wt repo root)
    let repo_id = (_wt repo id)
    let remote_url = (git -C $repo_root remote get-url origin | str trim)

    let selected_prs = (
        if ($pr | is-not-empty) {
            let pr_str = ($pr | into string | str trim)
            let view_res = (do {
                gh pr view $pr_str --json "number,title,headRefName,baseRefName"
            } | complete)
            if $view_res.exit_code != 0 {
                print $"Failed to find PR: ($pr_str)"
                return []
            }
            [($view_res.stdout | from json)]
        } else {
            let prs = (
                gh pr list --state open --json "number,title,headRefName,baseRefName"
                | from json
            )

            if ($prs | is-empty) {
                print "No open PRs found."
                return []
            }

            if $all {
                $prs
            } else {
                let choices = (
                    $prs
                    | each {|pr|
                        $"#($pr.number)  ($pr.headRefName) → ($pr.baseRefName)  ($pr.title)"
                    }
                )

                let selected_labels = (
                    $choices
                    | input list --fuzzy --multi "Select PRs to auto-merge"
                )

                if ($selected_labels | is-empty) {
                    return []
                }

                (if ($selected_labels | describe | str starts-with "list") { $selected_labels } else { [$selected_labels] })
                | each {|label|
                    let number = (
                        $label
                        | parse -r '^#(?<number>\d+)'
                        | get 0.number
                        | into int
                    )

                    $prs | where number == $number | get 0
                }
            }
        }
    )

    if ($selected_prs | is-empty) {
        return []
    }

    mut recap = []

    for pr in $selected_prs {
        print $"Processing PR #($pr.number): ($pr.title)..."

        mut live = (
            gh pr view $pr.number --json "state,number,title,headRefName,baseRefName,headRefOid,mergeStateStatus,mergeable,isDraft,reviewDecision,statusCheckRollup"
            | from json
        )

        mut retries = 0
        while ($live.state? == "OPEN") and ($live.mergeStateStatus == "UNKNOWN") and $retries < 3 {
            sleep 2sec
            $live = (
                gh pr view $pr.number --json "state,number,title,headRefName,baseRefName,headRefOid,mergeStateStatus,mergeable,isDraft,reviewDecision,statusCheckRollup"
                | from json
            )
            $retries += 1
        }

        if $live.state? == "MERGED" {
            print $"PR #($pr.number) is already merged."
            $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Merged", reason: "Already merged" })
            continue
        }

        if $live.state? == "CLOSED" {
            print $"PR #($pr.number) is closed."
            $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Failed", reason: "PR closed without merging" })
            continue
        }

        if $live.mergeStateStatus == "CLEAN" {
            print $"PR #($pr.number) is clean, merging..."
            let merge_res = (do { gh pr merge $pr.number --squash } | complete)
            if $merge_res.exit_code == 0 {
                print $"PR #($pr.number) merged successfully."
                $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Merged", reason: "Merged directly" })
            } else {
                let err = ($merge_res.stderr | str trim)
                print $"PR #($pr.number) merge failed: ($err)"
                $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Failed", reason: $"Merge error: ($err)" })
            }
            continue
        }

        let is_conflicting = ($live.mergeable == "CONFLICTING" or $live.mergeStateStatus == "DIRTY")
        let is_behind = ($live.mergeStateStatus == "BEHIND")
        let has_failed_ci = (_pr_has_failed_checks $live.statusCheckRollup)
        let needs_rebase_fix = (
            ($is_behind and $fix_behind_rebase)
            or ($is_conflicting and $fix_conflict)
        )

        if not $needs_rebase_fix {
            let is_draft = ($live.isDraft | default false)
            let is_running_ci = (_pr_has_running_checks $live.statusCheckRollup)

            let skip_reason = (
                if $is_draft {
                    "Draft PR"
                } else if $is_conflicting {
                    "Merge conflicts"
                } else if $is_behind {
                    "Behind target branch"
                } else if ($live.reviewDecision == "CHANGES_REQUESTED") {
                    "Changes requested"
                } else if ($live.reviewDecision == "REVIEW_REQUIRED" and (not $is_running_ci) and ($live.statusCheckRollup | default [] | is-not-empty)) {
                    "Review required"
                } else if ($has_failed_ci and (not $fix_ci)) {
                    "CI failing"
                } else {
                    ""
                }
            )

            if ($skip_reason | is-not-empty) {
                print $"PR #($pr.number) cannot be merged [($skip_reason)], skipping."
                $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Skipped", reason: $skip_reason })
                continue
            }

            mut ci_retried = false
            if $has_failed_ci and $fix_ci {
                print $"PR #($pr.number) has failing CI checks. Attempting --fix-ci rerun once..."
                let rerun_ok = (_pr_rerun_failed_ci $pr.number $live.headRefOid $live.statusCheckRollup)
                if not $rerun_ok {
                    $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Skipped", reason: "CI rerun failed to trigger" })
                    continue
                }
                $ci_retried = true
                print $"Rerun triggered for PR #($pr.number). Waiting for CI checks..."
                sleep 5sec
            } else {
                print $"Waiting for CI checks on PR #($pr.number)..."
            }

            mut pr_result = "Skipped"
            mut pr_reason = "Unknown"
            mut poll_count = 0
            let max_polls = 180

            loop {
                let view_res = (do {
                    gh pr view $pr.number --json "state,headRefOid,mergeStateStatus,mergeable,reviewDecision,statusCheckRollup"
                } | complete)

                if $view_res.exit_code != 0 {
                    sleep 5sec
                    continue
                }

                let poll_pr = ($view_res.stdout | from json)

                if ($poll_pr.state? == "MERGED") {
                    print $"PR #($pr.number) merged successfully."
                    $pr_result = "Merged"
                    $pr_reason = (if $ci_retried { "Reran CI and merged" } else { "Auto-merged after CI checks" })
                    break
                }

                if ($poll_pr.state? == "CLOSED") {
                    print $"PR #($pr.number) was closed without merging."
                    $pr_result = "Failed"
                    $pr_reason = "PR closed without merging"
                    break
                }

                if (_pr_has_failed_checks $poll_pr.statusCheckRollup) {
                    if $fix_ci and (not $ci_retried) {
                        $ci_retried = true
                        print $"CI checks failed on PR #($pr.number). Attempting --fix-ci rerun once..."
                        let rerun_ok = (_pr_rerun_failed_ci $pr.number $poll_pr.headRefOid $poll_pr.statusCheckRollup)
                        if $rerun_ok {
                            sleep 5sec
                            continue
                        }
                    }
                    print $"PR #($pr.number) CI checks failed."
                    $pr_result = "Skipped"
                    $pr_reason = (if $ci_retried { "CI failed after rerun" } else { "CI failed" })
                    break
                }

                if ($poll_pr.mergeable == "CONFLICTING" or $poll_pr.mergeStateStatus == "DIRTY") {
                    print $"PR #($pr.number) has conflicts."
                    $pr_result = "Skipped"
                    $pr_reason = "Merge conflicts"
                    break
                }

                if ($poll_pr.reviewDecision == "CHANGES_REQUESTED") {
                    print $"PR #($pr.number) has changes requested."
                    $pr_result = "Skipped"
                    $pr_reason = "Changes requested"
                    break
                }

                if ($poll_pr.reviewDecision == "REVIEW_REQUIRED") {
                    if (not (_pr_has_running_checks $poll_pr.statusCheckRollup)) and ($poll_pr.statusCheckRollup | default [] | is-not-empty) {
                        print $"PR #($pr.number) requires review."
                        $pr_result = "Skipped"
                        $pr_reason = "Review required"
                        break
                    }
                }

                if $poll_pr.mergeStateStatus == "CLEAN" {
                    print $"PR #($pr.number) is clean, merging..."
                    let merge_res = (do { gh pr merge $pr.number --squash } | complete)
                    if $merge_res.exit_code == 0 {
                        print $"PR #($pr.number) merged successfully."
                        $pr_result = "Merged"
                        $pr_reason = (if $ci_retried { "Reran CI and merged" } else { "Merged after CI checks" })
                    } else {
                        let err = ($merge_res.stderr | str trim)
                        print $"PR #($pr.number) merge failed: ($err)"
                        $pr_result = "Failed"
                        $pr_reason = $"Merge error: ($err)"
                    }
                    break
                }

                $poll_count += 1
                if $poll_count > $max_polls {
                    print $"PR #($pr.number) timed out waiting for merge."
                    $pr_result = "Failed"
                    $pr_reason = "Timeout waiting for CI / merge"
                    break
                }

                print $"Waiting for PR #($pr.number) [state: ($poll_pr.mergeStateStatus)]..."
                sleep 10sec
            }

            $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: $pr_result, reason: $pr_reason })
            continue
        }

        let timestamp = (date now | format date "%Y%m%dT%H%M%SZ")
        let work_dir = (
            "/tmp"
            | path join $"($repo_id)-pr-($pr.number)-($timestamp)"
        )

        print $"PR #($pr.number): Rebasing onto ($pr.baseRefName)..."
        git clone $repo_root $work_dir
        git -C $work_dir remote set-url origin $remote_url
        git -C $work_dir fetch origin
        git -C $work_dir checkout -B $pr.headRefName $"origin/($pr.headRefName)"

        let rebase_res = (do { git -C $work_dir rebase $"origin/($pr.baseRefName)" } | complete)
        mut had_conflicts = false

        if $rebase_res.exit_code != 0 {
            if not $fix_conflict {
                print $"PR #($pr.number) rebase conflict, skipping."
                try { git -C $work_dir rebase --abort }
                rm -rf $work_dir
                $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Skipped", reason: "Rebase conflicts" })
                continue
            }

            $had_conflicts = true
            print $"PR #($pr.number) rebase encountered conflicts. Resolving interactively..."
            let res_status = (_pr_resolve_rebase_conflicts $work_dir)
            if $res_status != "resolved" {
                rm -rf $work_dir
                $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Skipped", reason: $"Conflict resolution ($res_status)" })
                continue
            }
        }

        let new_head_sha = (git -C $work_dir rev-parse HEAD | str trim)
        let push_res = (do { git -C $work_dir push --force-with-lease origin $pr.headRefName } | complete)
        rm -rf $work_dir

        if $push_res.exit_code != 0 {
            let err = ($push_res.stderr | str trim)
            print $"PR #($pr.number) push failed: ($err)"
            $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: "Skipped", reason: $"Push failed: ($err)" })
            continue
        }

        print $"Pushed rebased PR #($pr.number). Waiting for mergeability..."
        sleep 5sec

        mut pr_result = "Updated (not merged)"
        mut pr_reason = "Unknown"
        mut ci_retried = false
        mut poll_count = 0
        let max_polls = 180

        loop {
            let view_res = (do {
                gh pr view $pr.number --json "state,headRefOid,mergeStateStatus,mergeable,reviewDecision,statusCheckRollup"
            } | complete)

            if $view_res.exit_code != 0 {
                sleep 5sec
                continue
            }

            let poll_pr = ($view_res.stdout | from json)

            if ($poll_pr.state? == "MERGED") {
                print $"PR #($pr.number) merged successfully."
                $pr_result = "Merged"
                $pr_reason = (if $had_conflicts { "Resolved conflicts and merged" } else { "Rebased and merged" })
                break
            }

            if ($poll_pr.state? == "CLOSED") {
                print $"PR #($pr.number) was closed without merging."
                $pr_result = "Failed"
                $pr_reason = "PR closed without merging"
                break
            }

            if ($poll_pr.headRefOid? != $new_head_sha) {
                sleep 5sec
                continue
            }

            if (_pr_has_failed_checks $poll_pr.statusCheckRollup) {
                if $fix_ci and (not $ci_retried) {
                    $ci_retried = true
                    print $"CI checks failed on rebased PR #($pr.number). Attempting --fix-ci rerun once..."
                    let rerun_ok = (_pr_rerun_failed_ci $pr.number $new_head_sha $poll_pr.statusCheckRollup)
                    if $rerun_ok {
                        sleep 5sec
                        continue
                    }
                }
                print $"PR #($pr.number) CI checks failed after rebase."
                $pr_result = "Updated (not merged)"
                $pr_reason = (if $ci_retried { "CI failed after rerun" } else { "CI failed after rebase" })
                break
            }

            if ($poll_pr.mergeable == "CONFLICTING" or $poll_pr.mergeStateStatus == "DIRTY") {
                print $"PR #($pr.number) has conflicts after rebase."
                $pr_result = "Updated (not merged)"
                $pr_reason = "Merge conflicts"
                break
            }

            if ($poll_pr.reviewDecision == "CHANGES_REQUESTED") {
                print $"PR #($pr.number) has changes requested."
                $pr_result = "Updated (not merged)"
                $pr_reason = "Changes requested"
                break
            }

            if ($poll_pr.reviewDecision == "REVIEW_REQUIRED") {
                if (not (_pr_has_running_checks $poll_pr.statusCheckRollup)) and ($poll_pr.statusCheckRollup | default [] | is-not-empty) {
                    print $"PR #($pr.number) requires review."
                    $pr_result = "Updated (not merged)"
                    $pr_reason = "Review required"
                    break
                }
            }

            if $poll_pr.mergeStateStatus == "CLEAN" {
                print $"PR #($pr.number) is clean, merging..."
                let merge_res = (do { gh pr merge $pr.number --squash } | complete)
                if $merge_res.exit_code == 0 {
                    print $"PR #($pr.number) merged successfully."
                    $pr_result = "Merged"
                    $pr_reason = (if $had_conflicts { "Resolved conflicts and merged" } else { "Rebased and merged" })
                } else {
                    let err = ($merge_res.stderr | str trim)
                    print $"PR #($pr.number) merge failed: ($err)"
                    $pr_result = "Failed"
                    $pr_reason = $"Merge error: ($err)"
                }
                break
            }

            $poll_count += 1
            if $poll_count > $max_polls {
                print $"PR #($pr.number) timed out waiting for merge."
                $pr_result = "Failed"
                $pr_reason = "Timeout waiting for CI / merge"
                break
            }

            print $"Waiting for PR #($pr.number) [state: ($poll_pr.mergeStateStatus)]..."
            sleep 10sec
        }

        $recap = ($recap | append { pr: $"#($pr.number)", title: $pr.title, branch: $pr.headRefName, result: $pr_result, reason: $pr_reason })
    }

    print "\n--- Recap ---"
    $recap
}
    '';
  };

  dotfiles.nushell.autoload = {
    "git-gh".text = ''
use ../modules/git-gh.nu *
    '';
  };
}
