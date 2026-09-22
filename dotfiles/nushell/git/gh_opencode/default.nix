{ ... }:

{
  dotfiles.nushell.modules = {
    "git-gh-opencode".text = ''
use ./git.nu *
use ./git-gh.nu [",g-gh prs-auto-merge"]

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
    '';
  };

  dotfiles.nushell.autoload = {
    "git-gh-opencode".text = ''
use ../modules/git-gh-opencode.nu *
    '';
  };
}
