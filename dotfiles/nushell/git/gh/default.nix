{ ... }:

{
  dotfiles.nushell.modules = {
    "git-gh".text = ''
use ./git.nu *

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
