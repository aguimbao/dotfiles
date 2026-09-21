{ ... }:

{
  dotfiles.nushell.modules = {
    "pass-cli".text = ''
def _pass-auth [] {
    pass-cli logout --force
    let token = (input --suppress-output "Proton Pass access token: ")

    if ($token | is-empty) {
        error make { msg: "No Proton Pass access token was provided." }
    }

    let login = (
        with-env { PROTON_PASS_PERSONAL_ACCESS_TOKEN: $token } {
            pass-cli login | complete
        }
    )

    if $login.exit_code != 0 {
        error make {
            msg: "Proton Pass login failed."
            label: {
                text: ($login.stderr | str trim)
                span: (metadata $login.stderr).span
            }
        }
    }
}

export def --wrapped ",pc" [...args] {
    pass-cli ...$args
}

export def ",pc pat-login" [] {
    if (pass-cli info | complete | get exit_code) != 0 {
        _pass-auth
    }
}

export def ",pc pat-login-refresh" [] {
    _pass-auth
}

export def ",pc pat-login-purge" [] {
    glob ($env.HOME | path join ".cache" "pass-cli-*")
    | where {|p| ($p | path type) == "dir" }
    | each { rm --recursive --force $in }
    | ignore

    let share_dir = ($env.HOME | path join ".local" "share" "proton-pass-cli")
    mkdir $share_dir
    ls --all $share_dir | get name | each { rm --recursive --force $in } | ignore
}

export def --env ",pc gsd" [action: closure] {
    with-env { PROTON_PASS_USE_GLOBAL_SESSION_DIR: "1" } {
        do $action
    }
}

export def --env ",pc gsdr" [action: closure] {
    with-env {
        PROTON_PASS_USE_GLOBAL_SESSION_DIR_TREE: "1"
        PROTON_PASS_SESSION_DIR: ($env.HOME | path join ".local" "share" "proton-pass-cli")
    } {
        do $action
    }
}

export def ",pc ssh-keys-load" [
    --vault: string = "Dev"
] {
    ^pass-cli ssh-agent load --vault-name $vault
}

const PASS_PAT_EXPIRATIONS = ["1h", "1d", "1w", "1m", "3m", "6m", "1y"]
const PASS_PAT_ROLES = ["viewer", "editor", "manager"]

def _pass-pat-list [] {
    let res = (^pass-cli pat list --output json | complete)
    if $res.exit_code != 0 {
        error make { msg: $"Failed to list Personal Access Tokens: ($res.stderr | str trim)" }
    }
    $res.stdout | from json
}

def _pass-pat-select [name?: string, id?: string] {
    if ($id != null) and not ($id | is-empty) {
        return { pat_id: $id, name: ($name | default $id) }
    }

    let pats = (_pass-pat-list)
    if ($pats | is-empty) {
        error make { msg: "No Personal Access Tokens found." }
    }

    if ($name != null) and not ($name | is-empty) {
        let match = ($pats | where name == $name)
        if ($match | is-empty) {
            error make { msg: $"No Personal Access Token found with name '($name)'." }
        }
        return ($match | first)
    }

    $pats
    | input list --fuzzy --display { |p|
        let exp = if ($p.expire_time? | default 0) > 0 {
            (($p.expire_time * 1_000_000_000) | into datetime | format date "%Y-%m-%d %H:%M")
        } else {
            "never"
        }
        $"($p.name) (expires: ($exp))"
    } "Select Personal Access Token:"
}

def _pass-vault-list [] {
    let res = (^pass-cli vault list --output json | complete)
    if $res.exit_code != 0 {
        error make { msg: $"Failed to list vaults: ($res.stderr | str trim)" }
    }
    let data = ($res.stdout | from json)
    $data.vaults? | default []
}

def _pass-item-list [vault?: string, share_id?: string] {
    let args = (
        if ($share_id != null) and not ($share_id | is-empty) {
            ["item", "list", "--share-id", $share_id, "--filter-state", "active", "--output", "json"]
        } else {
            ["item", "list", "--vault-name", $vault, "--filter-state", "active", "--output", "json"]
        }
    )
    let res = (^pass-cli ...$args | complete)
    if $res.exit_code != 0 {
        error make { msg: $"Failed to list items: ($res.stderr | str trim)" }
    }
    let data = ($res.stdout | from json)
    $data.items? | default []
}

export def ",pc pat-new" [
    --name (-n): string
    --expiration (-e): string
] {
    let pat_name = if ($name != null) and not ($name | is-empty) {
        $name
    } else {
        input "Personal access token name: " | str trim
    }

    if ($pat_name | is-empty) {
        print "Cancelled: name is required."
        return
    }

    let pat_expiration = if ($expiration != null) and not ($expiration | is-empty) {
        $expiration
    } else {
        $PASS_PAT_EXPIRATIONS | input list --fuzzy "Select token expiration:"
    }

    if ($pat_expiration == null) or ($pat_expiration | is-empty) {
        print "Cancelled: expiration is required."
        return
    }

    if $pat_expiration not-in $PASS_PAT_EXPIRATIONS {
        error make { msg: $"Invalid expiration '($pat_expiration)'. Valid options: ($PASS_PAT_EXPIRATIONS | str join ', ')" }
    }

    ^pass-cli pat create --name $pat_name --expiration $pat_expiration
}

export def ",pc pat-delete" [
    --name (-n): string
    --id (-i): string
    --yes (-y)
] {
    let target = (_pass-pat-select $name $id)
    if ($target == null) or ($target | is-empty) {
        return
    }

    let pat_id = $target.pat_id
    let pat_name = ($target.name? | default $pat_id)

    if not $yes {
        let answer = (input $"Are you sure you want to delete PAT '($pat_name)'? [y/N]: " | str trim | str lowercase)
        if $answer not-in ["y", "yes"] {
            print "Cancelled: token was not deleted."
            return
        }
    }

    ^pass-cli pat delete --personal-access-token-id $pat_id
}

export def ",pc pat-edit" [
    --name (-n): string
    --id (-i): string
    --expiration (-e): string
] {
    let target = (_pass-pat-select $name $id)
    if ($target == null) or ($target | is-empty) {
        return
    }

    let pat_id = $target.pat_id
    let pat_name = ($target.name? | default $pat_id)

    let pat_expiration = if ($expiration != null) and not ($expiration | is-empty) {
        $expiration
    } else {
        $PASS_PAT_EXPIRATIONS | input list --fuzzy $"Select new expiration for '($pat_name)':"
    }

    if ($pat_expiration == null) or ($pat_expiration | is-empty) {
        print "Cancelled: expiration is required."
        return
    }

    if $pat_expiration not-in $PASS_PAT_EXPIRATIONS {
        error make { msg: $"Invalid expiration '($pat_expiration)'. Valid options: ($PASS_PAT_EXPIRATIONS | str join ', ')" }
    }

    ^pass-cli pat renew --personal-access-token-id $pat_id --expiration $pat_expiration
}

export def ",pc pat-grants-list" [
    --name (-n): string
    --id (-i): string
    --raw
    --json
] {
    let target = (_pass-pat-select $name $id)
    if ($target == null) or ($target | is-empty) {
        return
    }

    let pat_id = $target.pat_id

    if $raw {
        ^pass-cli pat access list-access --personal-access-token-id $pat_id
    } else if $json {
        ^pass-cli pat access list-access --personal-access-token-id $pat_id --output json
    } else {
        let result = (^pass-cli pat access list-access --personal-access-token-id $pat_id --output json | complete)
        if $result.exit_code != 0 {
            error make { msg: $"Failed to list access grants: ($result.stderr | str trim)" }
        }
        let grants = ($result.stdout | from json)
        if ($grants | is-empty) {
            print $"No access grants found for PAT '($target.name? | default $pat_id)'."
            return
        }
        $grants
        | each { |g|
            let exp = if ($g.expire_time? | default 0) > 0 {
                (($g.expire_time * 1_000_000_000) | into datetime | format date "%Y-%m-%d %H:%M")
            } else {
                "never"
            }
            {
                type: $g.type?
                vault: $g.vault_name?
                item: ($g.item_title? | default ($g.title? | default "-"))
                role: $g.role?
                expires: $exp
                share_id: $g.share_id?
            }
        }
    }
}

export def ",pc pat-grants-edit" [
    --name (-n): string
    --id (-i): string
    --action (-a): string
    --vault (-v): string
    --vault-only
    --share-id: string
    --item: string
    --item-id: string
    --role (-r): string
] {
    let target = (_pass-pat-select $name $id)
    if ($target == null) or ($target | is-empty) {
        return
    }

    let pat_id = $target.pat_id
    let pat_name = ($target.name? | default $pat_id)

    let selected_action = if ($action != null) and not ($action | is-empty) {
        $action | str lowercase
    } else {
        ["grant", "revoke"] | input list --fuzzy $"Select action for PAT '($pat_name)':"
    }

    if ($selected_action == null) or ($selected_action | is-empty) {
        print "Cancelled: no action selected."
        return
    }

    if $selected_action == "grant" {
        mut grant_vault = $vault
        mut grant_share_id = $share_id

        if ($grant_vault == null) and ($grant_share_id == null) {
            let vaults = (_pass-vault-list)
            if ($vaults | is-empty) {
                error make { msg: "No vaults found." }
            }
            let chosen_vault = (
                $vaults
                | input list --fuzzy --display { |v| $v.name } "Select vault to grant access to:"
            )
            if ($chosen_vault == null) or ($chosen_vault | is-empty) {
                print "Cancelled: no vault selected."
                return
            }
            $grant_vault = $chosen_vault.name
        }

        mut grant_item = $item
        mut grant_item_id = $item_id

        if not $vault_only and ($grant_item == null) and ($grant_item_id == null) and (($grant_vault != null) or ($grant_share_id != null)) {
            let scope = (["Entire vault", "Specific item"] | input list --fuzzy $"Grant scope for vault '($grant_vault | default $grant_share_id)':")
            if ($scope == null) or ($scope | is-empty) {
                print "Cancelled: no scope selected."
                return
            }

            if $scope == "Specific item" {
                let items = (_pass-item-list $grant_vault $grant_share_id)
                if ($items | is-empty) {
                    print "No active items found; granting access to entire vault."
                } else {
                    let chosen_item = (
                        $items
                        | input list --fuzzy --display { |it| $it.title? | default ($it.name? | default $it.id) } "Select item to grant access to:"
                    )
                    if ($chosen_item == null) or ($chosen_item | is-empty) {
                        print "Cancelled: no item selected."
                        return
                    }
                    $grant_item = ($chosen_item.title? | default ($chosen_item.name? | default ""))
                    $grant_item_id = $chosen_item.id?
                }
            }
        }

        let grant_role = if ($role != null) and not ($role | is-empty) {
            $role | str lowercase
        } else {
            let chosen_role = ($PASS_PAT_ROLES | input list --fuzzy "Select role [default: viewer]:")
            if ($chosen_role == null) or ($chosen_role | is-empty) {
                "viewer"
            } else {
                $chosen_role
            }
        }

        if $grant_role not-in $PASS_PAT_ROLES {
            error make { msg: $"Invalid role '($grant_role)'. Valid roles: ($PASS_PAT_ROLES | str join ', ')" }
        }

        mut grant_args = ["pat", "access", "grant", "--personal-access-token-id", $pat_id]

        if ($grant_share_id != null) and not ($grant_share_id | is-empty) and ($grant_vault == null) {
            $grant_args = ($grant_args | append ["--share-id", $grant_share_id])
        } else if ($grant_vault != null) and not ($grant_vault | is-empty) {
            $grant_args = ($grant_args | append ["--vault-name", $grant_vault])
        }

        if ($grant_item_id != null) and not ($grant_item_id | is-empty) {
            $grant_args = ($grant_args | append ["--item-id", $grant_item_id])
        } else if ($grant_item != null) and not ($grant_item | is-empty) {
            $grant_args = ($grant_args | append ["--item-title", $grant_item])
        }

        $grant_args = ($grant_args | append ["--role", $grant_role])

        ^pass-cli ...$grant_args
    } else if $selected_action == "revoke" {
        mut revoke_share_id = $share_id

        if ($revoke_share_id == null) or ($revoke_share_id | is-empty) {
            let res = (^pass-cli pat access list-access --personal-access-token-id $pat_id --output json | complete)
            if $res.exit_code != 0 {
                error make { msg: $"Failed to list access grants: ($res.stderr | str trim)" }
            }
            let grants = ($res.stdout | from json)
            if ($grants | is-empty) {
                print $"No access grants found to revoke for PAT '($pat_name)'."
                return
            }

            let filtered_grants = if ($vault != null) and not ($vault | is-empty) {
                $grants | where vault_name == $vault
            } else {
                $grants
            }

            if ($filtered_grants | is-empty) {
                error make { msg: $"No access grants match vault '($vault)'." }
            }

            let chosen_grant = if ($filtered_grants | length) == 1 and ($vault != null) {
                $filtered_grants | first
            } else {
                $filtered_grants
                | input list --fuzzy --display { |g|
                    let target_desc = if ($g.item_title? != null) {
                        $"Item '($g.item_title)' in vault '($g.vault_name?)'"
                    } else if ($g.title? != null) {
                        $"Item '($g.title)' in vault '($g.vault_name?)'"
                    } else {
                        $"Vault '($g.vault_name?)'"
                    }
                    let short_share_id = ($g.share_id | str substring 0..12)
                    $"[($g.type)] ($target_desc) - Role: ($g.role) (share: ($short_share_id + '...'))"
                } $"Select grant to revoke for PAT '($pat_name)':"
            }

            if ($chosen_grant == null) or ($chosen_grant | is-empty) {
                print "Cancelled: no grant selected."
                return
            }

            $revoke_share_id = $chosen_grant.share_id
        }

        ^pass-cli pat access revoke --personal-access-token-id $pat_id --share-id $revoke_share_id
    } else {
        error make { msg: $"Invalid action '($selected_action)'. Valid: grant, revoke" }
    }
}

def _pass-item-field-names [detail: record] {
    mut fields = (_pass-custom-field-names $detail)
    let content = ($detail.item?.content? | default {})
    if ($content.content?.Login?.username? != null) { $fields = ($fields | append "username") }
    if ($content.content?.Login?.password? != null) { $fields = ($fields | append "password") }
    if ($content.content?.Login?.totp? != null) { $fields = ($fields | append "totp") }
    if ($content.note? != null) and not ($content.note | is-empty) { $fields = ($fields | append "note") }
    $fields | uniq
}

def _pass-accessible-items [] {
    let share_res = (^pass-cli share list --output json | complete)
    let shares = (
        if $share_res.exit_code == 0 {
            try { $share_res.stdout | from json | get shares? | default [] } catch { [] }
        } else {
            []
        }
    )

    let all_shares = (
        if not ($shares | is-empty) {
            $shares
        } else {
            let vault_res = (^pass-cli vault list --output json | complete)
            if $vault_res.exit_code == 0 {
                try {
                    let vd = ($vault_res.stdout | from json)
                    $vd.vaults? | default [] | each { |v| { id: $v.share_id, name: $v.name } }
                } catch { [] }
            } else {
                []
            }
        }
    )

    if ($all_shares | is-empty) {
        error make { msg: "No accessible shares or vaults found." }
    }

    $all_shares
    | each { |s|
        let item_res = (^pass-cli item list --share-id $s.id --filter-state active --output json | complete)
        if $item_res.exit_code == 0 {
            let items_data = (try { $item_res.stdout | from json | get items? | default [] } catch { [] })
            $items_data
            | each { |it|
                let title = ($it.title? | default ($it.name? | default $it.id))
                let sname = ($s.name? | default "")
                let short_sid = (($s.id | str substring 0..10) + "...")
                {
                    item: $title
                    share: $sname
                    share_id: $short_sid
                    share_type: ($s.share_type? | default "Vault")
                    full_share_id: $s.id
                    full_item_id: $it.id
                    full_item_title: $title
                    full_share_name: $sname
                    item_type: ($it.item_type? | default "")
                }
            }
        } else {
            []
        }
    }
    | flatten
}

export def ",pc pat-grants-credential-format" [
    --item (-i): string             # Item title or item ID
    --share (-s): string            # Share name or share ID
    --field (-f): string            # Field name (e.g. API_KEY)
    --all (-a)                      # Output all fields for the item
    --uri (-u)                      # Prefix with "pass://"
    --names                         # Force human-readable names format (Vault/Item/Field)
    --ids                           # Force IDs format (ShareID/ItemID/Field)
] {
    let items = (_pass-accessible-items)
    if ($items | is-empty) {
        error make { msg: "No accessible items found in any share." }
    }

    mut filtered_items = $items
    if ($share != null) and not ($share | is-empty) {
        $filtered_items = (
            $filtered_items
            | where { |it|
                (($it.full_share_name == $share)
                or (($it.full_share_name | str lowercase) == ($share | str lowercase))
                or ($it.full_share_id == $share)
                or ($it.share_id == $share))
            }
        )
        if ($filtered_items | is-empty) {
            error make { msg: $"No items found in share '($share)'." }
        }
    }

    if ($item != null) and not ($item | is-empty) {
        $filtered_items = (
            $filtered_items
            | where { |it|
                (($it.full_item_title == $item)
                or (($it.full_item_title | str lowercase) == ($item | str lowercase))
                or ($it.full_item_id == $item))
            }
        )
        if ($filtered_items | is-empty) {
            error make { msg: $"No item found matching '($item)'." }
        }
    }

    let selected_item = if ($filtered_items | length) == 1 {
        $filtered_items | first
    } else {
        $filtered_items
        | input list --fuzzy --display { |it|
            $"($it.item) (share: ($it.share), id: ($it.share_id))"
        } "Select item:"
    }

    if ($selected_item == null) or ($selected_item | is-empty) {
        print "Cancelled: no item selected."
        return
    }

    let detail_res = (^pass-cli item view --share-id $selected_item.full_share_id --item-id $selected_item.full_item_id --output json | complete)
    if $detail_res.exit_code != 0 {
        error make { msg: $"Failed to view item: ($detail_res.stderr | str trim)" }
    }

    let detail = (
        try {
            $detail_res.stdout | from json
        } catch {
            error make { msg: "Failed to parse item JSON." }
        }
    )

    let available_fields = (_pass-item-field-names $detail)
    if ($available_fields | is-empty) {
        error make { msg: $"No fields found on item '($selected_item.full_item_title)'." }
    }

    let fields_to_format = if ($field != null) and not ($field | is-empty) {
        let matched = (
            $available_fields
            | where { |af|
                $af == $field or ($af | str lowercase) == ($field | str lowercase)
            }
        )
        if ($matched | is-empty) {
            error make { msg: $"Field '($field)' not found on item. Available: ($available_fields | str join ', ')" }
        }
        $matched
    } else if $all or ($available_fields | length) == 1 {
        $available_fields
    } else {
        let chosen = ($available_fields | input list --fuzzy $"Select field for '($selected_item.full_item_title)':")
        if ($chosen == null) or ($chosen | is-empty) {
            print "Cancelled: no field selected."
            return
        }
        [$chosen]
    }

    let is_vault_share = ($selected_item.share_type == "Vault")
    let format_mode = if $names {
        if not $is_vault_share {
            error make { msg: $"Item '($selected_item.full_item_title)' is on an item-only grant and cannot be referenced by vault name. Use IDs format instead." }
        }
        "names"
    } else if $ids {
        "ids"
    } else if not $is_vault_share {
        "ids"
    } else {
        let choice = (["Names (Vault/Item/Field)", "IDs (ShareID/ItemID/Field)"] | input list --fuzzy "Select path format:")
        if ($choice == null) or ($choice | is-empty) {
            print "Cancelled: no format selected."
            return
        }
        if ($choice | str starts-with "Names") {
            "names"
        } else {
            "ids"
        }
    }

    let path_base = if $format_mode == "names" {
        $"($selected_item.full_share_name)/($selected_item.full_item_title)"
    } else {
        $"($selected_item.full_share_id)/($selected_item.full_item_id)"
    }

    let prefix = if $uri { "pass://" } else { "" }
    let results = (
        $fields_to_format
        | each { |target_field|
            $"($prefix)($path_base)/($target_field)"
        }
    )

    if ($results | length) == 1 {
        $results | first
    } else {
        $results
    }
}

def _pass-scope [prompt: string] {
    let raw = (input $prompt | str trim)

    if ($raw | is-empty) {
        []
    } else {
        $raw
        | split row ","
        | each { |value| $value | str trim }
        | where { |value| not ($value | is-empty) }
    }
}

def _pass-matches-exactly [text: string, selectors: list<string>] {
    if ($selectors | is-empty) {
        true
    } else {
        $selectors | any { |selector| $text == $selector }
    }
}

def _pass-custom-field-names [item_json: record] {
    let extra_fields = (
        $item_json.item?.content?.extra_fields?
        | default []
    )

    $extra_fields
    | each { |field| $field.name? }
    | where { |name| $name != null }
    | where { |name| not ($name | is-empty) }
    | uniq
}

export def ",pc value-find" [
    --value (-V): string             # Exact sensitive value to find. Omit for hidden interactive input.
    --vault (-v): string             # Exact vault name, or comma-separated vault names.
    --item (-i): string              # Exact item title, or comma-separated item titles.
    --section (-s): string           # Exact section name, or comma-separated section names.
    --field (-f): string             # Exact field name, or comma-separated field names.

    --all-vaults                     # Search all accessible vaults. Overrides --vault.
    --all-items                      # Search all items in selected vaults. Overrides --item.
    --all-sections                   # Search all sections. Overrides --section.
    --all-fields                     # Search all discovered custom fields. Overrides --field.

    --yes (-y)                       # Skip confirmation.
] {
    let flag_mode = (
        ($value != null)
        or ($vault != null)
        or ($item != null)
        or ($section != null)
        or ($field != null)
        or $all_vaults
        or $all_items
        or $all_sections
        or $all_fields
    )

    let target = (
        if $value == null {
            input --suppress-output "Value to find (hidden): "
        } else {
            $value
        }
    )

    if ($target | is-empty) {
        error make {
            msg: "No value was supplied; nothing was searched."
        }
    }

    let vault_selectors = (
        if $all_vaults {
            []
        } else if $vault != null {
            $vault
            | split row ","
            | each { |entry| $entry | str trim }
            | where { |entry| not ($entry | is-empty) }
        } else if not $flag_mode {
            _pass-scope "Vault name(s), comma-separated [all]: "
        } else {
            []
        }
    )

    let item_selectors = (
        if $all_items {
            []
        } else if $item != null {
            $item
            | split row ","
            | each { |entry| $entry | str trim }
            | where { |entry| not ($entry | is-empty) }
        } else if not $flag_mode {
            _pass-scope "Item title(s), comma-separated [all]: "
        } else {
            []
        }
    )

    let section_selectors = (
        if $all_sections {
            []
        } else if $section != null {
            $section
            | split row ","
            | each { |entry| $entry | str trim }
            | where { |entry| not ($entry | is-empty) }
        } else if not $flag_mode {
            _pass-scope "Section name(s), comma-separated [all]: "
        } else {
            []
        }
    )

    let field_selectors = (
        if $all_fields {
            []
        } else if $field != null {
            $field
            | split row ","
            | each { |entry| $entry | str trim }
            | where { |entry| not ($entry | is-empty) }
        } else if not $flag_mode {
            _pass-scope "Field name(s), comma-separated [all]: "
        } else {
            []
        }
    )

    let scope_description = {
        vaults: (
            if $all_vaults {
                "all via --all-vaults"
            } else if ($vault_selectors | is-empty) {
                "all"
            } else {
                $vault_selectors | str join ", "
            }
        )

        items: (
            if $all_items {
                "all via --all-items"
            } else if ($item_selectors | is-empty) {
                "all"
            } else {
                $item_selectors | str join ", "
            }
        )

        sections: (
            if $all_sections {
                "all via --all-sections"
            } else if ($section_selectors | is-empty) {
                "all"
            } else {
                $section_selectors | str join ", "
            }
        )

        fields: (
            if $all_fields {
                "all via --all-fields"
            } else if ($field_selectors | is-empty) {
                "all"
            } else {
                $field_selectors | str join ", "
            }
        )
    }

    print "This is a read-only search."
    print "Vault, item, section, and field names are matched exactly."
    print "The target value and matching stored values will not be displayed."
    print $"Scope: ($scope_description | to json)"

    if not $yes {
        let answer = (
            input "Continue? [y/N]: "
            | str trim
            | str lowercase
        )

        if $answer not-in ["y", "yes"] {
            print "Cancelled; no Proton Pass content was queried."
            return
        }
    }

    let vault_result = (
        ^pass-cli vault list --output json
        | complete
    )

    if $vault_result.exit_code != 0 {
        error make {
            msg: $"Could not list Proton Pass vaults: ($vault_result.stderr | str trim)"
        }
    }

    let vault_response = (
        try {
            $vault_result.stdout | from json
        } catch {
            error make {
                msg: "Could not parse JSON from `pass-cli vault list --output json`."
            }
        }
    )

    let vaults = (
        $vault_response.vaults?
        | default []
    )

    if ($vaults | is-empty) {
        print "No accessible Proton Pass vaults were returned."
        return
    }

    mut inspected_vaults = 0
    mut inspected_items = 0
    mut skipped_items = 0

    for vault_record in $vaults {
        let vault_name = (
            $vault_record.name?
            | default (
                $vault_record.vault_name?
                | default (
                    $vault_record.vaultName?
                    | default ""
                )
            )
        )

        if ($vault_name | is-empty) {
            print "Warning: skipped a vault record without a name."
            continue
        }

        if not (_pass-matches-exactly $vault_name $vault_selectors) {
            continue
        }

        $inspected_vaults = $inspected_vaults + 1

        let item_result = (
            ^pass-cli item list --vault-name $vault_name --output json
            | complete
        )

        if $item_result.exit_code != 0 {
            print $"Warning: could not list items in vault \"($vault_name)\"."
            print $"pass-cli error: ($item_result.stderr | str trim)"
            continue
        }

        let item_response = (
            try {
                $item_result.stdout | from json
            } catch {
                print $"Warning: could not parse item JSON for vault \"($vault_name)\"."
                {}
            }
        )

        let items = (
            $item_response.items?
            | default []
        )

        for listed_item in $items {
            let item_title = (
                $listed_item.content?.title?
                | default (
                    $listed_item.title?
                    | default (
                        $listed_item.name?
                        | default ""
                    )
                )
            )

            if ($item_title | is-empty) {
                $skipped_items = $skipped_items + 1
                continue
            }

            if not (_pass-matches-exactly $item_title $item_selectors) {
                continue
            }

            $inspected_items = $inspected_items + 1

            let base_fields = (
                if ($field_selectors | is-empty) {
                    let detail_result = (
                        ^pass-cli item view --vault-name $vault_name --item-title $item_title --output json
                        | complete
                    )

                    if $detail_result.exit_code != 0 {
                        print $"Warning: could not inspect item \"($item_title)\" in vault \"($vault_name)\"."
                        print $"pass-cli error: ($detail_result.stderr | str trim)"

                        $skipped_items = $skipped_items + 1
                        []
                    } else {
                        let detail = (
                            try {
                                $detail_result.stdout | from json
                            } catch {
                                print $"Warning: could not parse item JSON for \"($item_title)\" in vault \"($vault_name)\"."
                                {}
                            }
                        )

                        _pass-custom-field-names $detail
                    }
                } else {
                    $field_selectors
                }
            )

            if ($base_fields | is-empty) {
                continue
            }

            let fields_to_check = (
                if ($section_selectors | is-empty) {
                    $base_fields
                } else {
                    $section_selectors
                    | each { |section_name|
                        $base_fields
                        | each { |field_name|
                            $"($section_name).($field_name)"
                        }
                    }
                    | flatten
                    | uniq
                }
            )

            $fields_to_check
            | par-each { |field_name|
                let field_result = (
                    ^pass-cli item view --vault-name $vault_name --item-title $item_title --field $field_name
                    | complete
                )

                if $field_result.exit_code != 0 {
                    return
                }

                let candidate = (
                    $field_result.stdout
                    | str trim
                )

                if $candidate == $target {
                    print $"MATCH vault=($vault_name) item=($item_title) field=($field_name)"
                }
            }
            | ignore
        }
    }

    print ""
    print $"Inspected ($inspected_vaults) vaults."
    print $"Inspected ($inspected_items) items."

    if $skipped_items > 0 {
        print $"Skipped ($skipped_items) items that could not be read."
    }

    print "Search complete."
}
    '';
  };

  dotfiles.nushell.autoload = {
    "pass-cli".text = ''
use ../modules/pass-cli.nu *
    '';
  };
}
