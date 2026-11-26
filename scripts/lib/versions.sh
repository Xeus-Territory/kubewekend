#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# Kubewekend CLI library: versions command
# =============================================================================
# List, bump and sync the pinned versions (the table itself is in versions_registry.sh).
# Sourced by scripts/setup.sh (never run it directly). Functions only: nothing here runs until main() calls it.
# PROJECT_ROOT, HOST_VARS_DIR and the other path variables come from setup.sh; colours and info/warn/error from core.sh.

# Registry entry for a component name (empty + non-zero when unknown)
_ver_entry() {
    local entry
    for entry in "${VERSION_REGISTRY[@]}"; do
        [[ "${entry%%|*}" == "$1" ]] && { printf '%s' "$entry"; return 0; }
    done
    return 1
}

# Note (6th field) of a registry entry, empty when not set
_ver_note() {
    local -a f
    IFS='|' read -r -a f <<< "$1"
    printf '%s' "${f[5]:-}"
}

# Locate every pin of a registry entry: prints "relative/file|line|version", one per pin (sorted, unique)
_ver_locate() {
    local name group files anchor extract note g f n i ln v
    IFS='|' read -r name group files anchor extract note <<< "$1"
    [[ -n "$extract" ]] || extract='--version ([0-9v][^ ]*)'   # Helm charts
    local -a globs
    read -r -a globs <<< "$files"
    {
        for g in "${globs[@]}"; do
            for f in $(cd "$PROJECT_ROOT" && compgen -G "$g" || true); do
                while IFS=: read -r n _; do
                    # The version sits on the anchor line or one of the next 4 lines
                    i=0
                    # `|| [[ -n $ln ]]` keeps a last line that has no trailing newline
                    while IFS= read -r ln || [[ -n "$ln" ]]; do
                        v=$(sed -nE "s#.*${extract}.*#\1#p" <<< "$ln")
                        if [[ -n "$v" ]]; then
                            printf '%s|%s|%s\n' "$f" "$((n + i))" "$v"
                            break
                        fi
                        i=$((i + 1))
                    done < <(sed -n "${n},$((n + 4))p" "$PROJECT_ROOT/$f")
                done < <(grep -nE -- "$anchor" "$PROJECT_ROOT/$f" | grep -vE '^[0-9]+:[[:space:]]*#' || true)
            done
        done
    } | sort -t'|' -k1,1 -k2,2n -u
}

# Replace every literal occurrence of <old> with <new> on one line of a file.
# Keeps the file permissions and a missing trailing newline, so only the version line changes.
# shellcheck disable=SC2178,SC2128  # false positive: `tmp` is a plain local string here
_ver_replace_line() {
    local file="$1" line="$2" old="$3" new="$4" tmp
    tmp=$(mktemp)
    awk -v n="$line" -v old="$old" -v new="$new" '
        NR == n {
            out = ""; s = $0
            while ((i = index(s, old)) > 0) { out = out substr(s, 1, i - 1) new; s = substr(s, i + length(old)) }
            $0 = out s
        }
        { print }' "$file" > "$tmp"
    if [[ -n "$(tail -c1 "$file")" ]]; then
        head -c -1 "$tmp" > "$file"   # original had no trailing newline: drop the one awk added
    else
        cat "$tmp" > "$file"
    fi
    rm -f "$tmp"
}

# Disclaimer shown before every bump
_ver_disclaimer() {
    printf "\n  ${BOLD}${YELLOW}DISCLAIMER — bumping versions is at your own risk${NC}\n"
    cat <<'EOF'
  Kubewekend only tests the versions pinned in this repository. A newer chart or tool can change its
  templates, values and defaults, drop support for your Kubernetes version, or stop matching the
  Kubewekend playbooks and value templates (ansible/templates/*-values.yaml.j2), and can break the
  setup, the utilities or an upgrade of a running cluster.
  Before bumping: read the release notes / upgrade guide, preview with --dry-run, and try it on a
  disposable cluster first. You decide whether to keep, adjust or revert the change.
EOF
    echo ""
}

# `versions list [filter]`: current pinned versions and where they live
versions_list() {
    local filter="${1:-}" entry name group current_group="" locs versions where mixed note count=0
    header "Kubewekend pinned versions"
    printf "  Source of truth: the files below; overview with notes in README.md → Versions\n"
    for entry in "${VERSION_REGISTRY[@]}"; do
        IFS='|' read -r name group _ <<< "$entry"
        if [[ -n "$filter" && "$name" != *"$filter"* && "$group" != "$filter" ]]; then continue; fi
        if [[ "$group" != "$current_group" ]]; then
            _sec "${group^^}"
            current_group="$group"
        fi
        locs=$(_ver_locate "$entry")
        count=$((count + 1))
        if [[ -z "$locs" ]]; then
            printf "  ${CYAN}%-24s${NC} %s\n" "$name" "${RED}not found (pattern needs an update)${NC}"
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u | paste -sd, - | sed 's/,/, /g')
        mixed=""
        [[ "$versions" == *,* ]] && mixed="  ${YELLOW}(mixed versions)${NC}"
        # Group locations per file: file:l1,l2
        where=$(awk -F'|' '{ sub(/^ansible\//, "", $1); a[$1] = (a[$1] ? a[$1] "," : "") $2; if (!($1 in o)) { o[$1] = ++k; f[k] = $1 } }
            END { for (j = 1; j <= k; j++) printf "%s%s:%s", (j > 1 ? "  " : ""), f[j], a[f[j]] }' <<< "$locs")
        printf "  ${CYAN}%-24s${NC} %s%s\n" "$name" "$(_cur "$versions")" "$mixed"
        printf "  %-24s %s\n" "" "$where"
        note=$(_ver_note "$entry")
        [[ -n "$note" ]] && printf "  %-24s ${YELLOW}note:${NC} %s\n" "" "$note"
    done
    [[ "$count" -gt 0 ]] || warn "No component matches '$filter' (groups: kubernetes, host-tools, networking, utilities, templates, charts, examples, repo-tooling)"
    echo ""
    info "Bump: ./scripts/setup.sh versions bump <component> <new-version> [--dry-run]"
    echo "  Not tracked (hand-written in README.md): kubectl (latest) / Helm (V3 latest) / Calico (latest) / Flux CLI (latest)"
}

# `versions bump <component> <new-version> [--dry-run] [--yes]`
versions_bump() {
    local name="" new="" dry_run=false assume_yes=false arg entry locs file line old changed=0
    for arg in "$@"; do
        case "$arg" in
            --dry-run) dry_run=true ;;
            --yes|-y)  assume_yes=true ;;
            -*)        warn "Unknown option: $arg" ;;
            *)         if [[ -z "$name" ]]; then name="$arg"; elif [[ -z "$new" ]]; then new="$arg"; fi ;;
        esac
    done
    if [[ -z "$name" || -z "$new" ]]; then
        error "Usage: ./scripts/setup.sh versions bump <component> <new-version> [--dry-run] [--yes]"
        echo "  Components: ./scripts/setup.sh versions list"
        return 1
    fi
    if ! entry=$(_ver_entry "$name"); then
        error "Unknown component: $name"
        echo "  Components: ./scripts/setup.sh versions list"
        return 1
    fi
    locs=$(_ver_locate "$entry")
    if [[ -z "$locs" ]]; then
        error "No pin found for '$name' (the registry pattern may need an update)"
        return 1
    fi

    header "Bump $name → $new"
    _ver_disclaimer
    local note
    note=$(_ver_note "$entry")
    if [[ -n "$note" ]]; then
        printf "  ${BOLD}Kubewekend configuration:${NC} %s\n\n" "$note"
    fi

    # Keep the `v` prefix style consistent with the current pins
    old=$(head -1 <<< "$locs" | cut -d'|' -f3)
    if [[ "${old:0:1}" == "v" && "${new:0:1}" != "v" ]] || [[ "${old:0:1}" != "v" && "${new:0:1}" == "v" ]]; then
        warn "Current pins look like '$old' but the new version is '$new' (check the 'v' prefix)"
    fi

    echo "  Changes:"
    while IFS='|' read -r file line old; do
        if [[ "$old" == "$new" ]]; then
            printf "    %-48s %s\n" "$file:$line" "already $new"
        else
            printf "    %-48s %s → %s\n" "$file:$line" "$old" "$(_cur "$new")"
            changed=$((changed + 1))
        fi
    done <<< "$locs"
    echo ""

    if [[ "$changed" -eq 0 ]]; then
        info "Nothing to change: $name is already $new"
        return 0
    fi
    if [[ "$dry_run" == true ]]; then
        info "[DRY RUN] $changed line(s) would change; no file was modified"
        return 0
    fi
    if [[ "$assume_yes" != true ]]; then
        confirm "Apply $changed change(s) for $name? You accept the risk described above" || { info "Aborted, nothing changed"; return 0; }
    fi

    while IFS='|' read -r file line old; do
        [[ "$old" == "$new" ]] || _ver_replace_line "$PROJECT_ROOT/$file" "$line" "$old" "$new"
    done <<< "$locs"
    info "Bumped $name to $new in $changed line(s)"
    echo "  Next: review with 'git diff', run './scripts/setup.sh versions sync' (or commit: the pre-commit hook runs it)"
    echo "        to refresh the README.md Versions table, and test on a disposable cluster"
}

# Title of a registry group in README.md
_ver_group_title() {
    case "$1" in
        kubernetes)   echo "Kubernetes distributions" ;;
        host-tools)   echo "Host tools" ;;
        networking)   echo "Cluster networking" ;;
        utilities)    echo "Utilities" ;;
        templates)    echo "Image pins in templates" ;;
        charts)       echo "Helm charts in this repository" ;;
        examples)     echo "Examples" ;;
        repo-tooling) echo "Repository tooling" ;;
        *)            echo "$1" ;;
    esac
}

# Markdown tables of every registry entry (the generated part of README.md → Versions)
_ver_markdown() {
    local entry name group current_group="" locs versions where
    for entry in "${VERSION_REGISTRY[@]}"; do
        IFS='|' read -r name group _ <<< "$entry"
        if [[ "$group" != "$current_group" ]]; then
            [[ -n "$current_group" ]] && echo ""
            echo "#### $(_ver_group_title "$group")"
            echo ""
            echo "| Component | Version | Where to update | Notes |"
            echo "| --------- | ------- | --------------- | ----- |"
            current_group="$group"
        fi
        locs=$(_ver_locate "$entry")
        if [[ -z "$locs" ]]; then
            echo "| \`$name\` | not found | pattern in \`VERSION_REGISTRY\` needs an update | |"
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g')
        # file:l1,l2 per file, in a code span
        where=$(awk -F'|' '{ a[$1] = (a[$1] ? a[$1] "," : "") $2; if (!($1 in o)) { o[$1] = ++k; f[k] = $1 } }
            END { for (j = 1; j <= k; j++) printf "%s`%s:%s`", (j > 1 ? ", " : ""), f[j], a[f[j]] }' <<< "$locs")
        echo "| \`$name\` | $versions | $where | $(_ver_note "$entry") |"
    done
}

# Validate the registry against the files: every entry must be found and pinned to one version.
# Prints one line per problem; returns the number of problems.
_ver_validate() {
    local entry name locs versions problems=0
    for entry in "${VERSION_REGISTRY[@]}"; do
        name="${entry%%|*}"
        locs=$(_ver_locate "$entry")
        if [[ -z "$locs" ]]; then
            error "$name: no pin found (update its pattern in VERSION_REGISTRY or remove the entry)"
            problems=$((problems + 1))
            continue
        fi
        versions=$(cut -d'|' -f3 <<< "$locs" | sort -u)
        if [[ $(wc -l <<< "$versions") -gt 1 ]]; then
            error "$name: pinned to different versions:"
            awk -F'|' '{ printf "          %s:%s  %s\n", $1, $2, $3 }' <<< "$locs" >&2
            echo "        fix: ./scripts/setup.sh versions bump $name <version>" >&2
            problems=$((problems + 1))
        fi
    done
    return "$problems"
}

# `versions sync [--check]`: validate the pins and regenerate the Versions tables (between the markers) in
# every VERSION_SYNC_TARGETS file. Pre-commit friendly: rewrites a stale file (the hook then reports the
# modified file); with --check (CI) it only reports. Exits 1 on validation problems or, with --check, a stale file.
versions_sync() {
    local check=false begin="<!-- versions:begin -->" end="<!-- versions:end -->"
    local generated current tmp target file problems=0 rc=0
    [[ "${1:-}" == "--check" ]] && check=true
    if ! grep -qxF "$begin" "$PROJECT_ROOT/README.md" || ! grep -qxF "$end" "$PROJECT_ROOT/README.md"; then
        error "README.md is missing the '$begin' / '$end' markers around the generated Versions tables"
        return 1
    fi

    _ver_validate || problems=$?

    generated=$(_ver_markdown)
    # Exact block between the markers: blank lines around the tables keep the end marker out of the last
    # table (kramdown on the docs site otherwise renders that table as plain text). The trailing `x`
    # sentinel stops $(...) from stripping the final blank line.
    local block
    block=$(printf '\n%s\n\n' "$generated"; echo x); block=${block%x}
    for target in "${VERSION_SYNC_TARGETS[@]}"; do
        file="$PROJECT_ROOT/$target"
        [[ -f "$file" ]] || continue
        if ! grep -qxF "$begin" "$file" || ! grep -qxF "$end" "$file"; then
            error "$target is missing the '$begin' / '$end' markers around the generated Versions tables"
            rc=1
            continue
        fi
        current=$(awk -v b="$begin" -v e="$end" '$0 == e { f = 0 } f { print } $0 == b { f = 1 }' "$file"; echo x)
        current=${current%x}
        if [[ "$block" == "$current" ]]; then
            info "$target Versions table is up to date"
        elif [[ "$check" == true ]]; then
            error "$target Versions table is out of date: run ./scripts/setup.sh versions sync"
            rc=1
        else
            tmp=$(mktemp)
            printf '%s' "$block" > "$tmp"
            awk -v b="$begin" -v e="$end" -v gen="$tmp" '
                $0 == b { print; while ((getline line < gen) > 0) print line; skip = 1; next }
                $0 == e { skip = 0 }
                !skip { print }' "$file" > "$tmp.out"
            cat "$tmp.out" > "$file"
            rm -f "$tmp" "$tmp.out"
            info "Updated $target Versions table (review and stage it)"
        fi
    done

    if [[ "$problems" -gt 0 ]]; then
        error "$problems version problem(s) found"
        return 1
    fi
    return "$rc"
}

cmd_versions_help() {
    cat <<'EOF'
kubewekend versions - List and bump pinned versions of charts, tools and manifests

SUBCOMMANDS
  list [filter]                         Current pinned versions and their file:line locations
                                        filter: component name or group (kubernetes, host-tools,
                                        networking, utilities)
  bump <component> <version> [opts]     Replace the pinned version everywhere it is used
  sync [--check]                        Validate the pins (found, one version each) and regenerate the
                                        Versions tables in README.md and docs/reference/versions.md;
                                        --check only reports (CI).
                                        Runs as a pre-commit hook (.pre-commit-config.yaml)

OPTIONS (bump)
  --dry-run                             Show the changes without modifying files
  --yes, -y                             Skip the confirmation prompt

DISCLAIMER
  Bumping is at your own risk: Kubewekend only tests the versions pinned in this repository. A newer
  chart or tool can change templates, values or defaults and stop working with the Kubewekend
  playbooks and value templates. Read the release notes, use --dry-run, and test on a disposable
  cluster first.

EXAMPLES
  ./scripts/setup.sh versions list
  ./scripts/setup.sh versions list networking
  ./scripts/setup.sh versions bump cilium 1.20.6 --dry-run
  ./scripts/setup.sh versions bump k3s v1.35.8+k3s1
EOF
}

cmd_versions() {
    local sub="${1:-help}"; shift || true
    case "$sub" in
        list|ls) versions_list "$@" ;;
        bump)    versions_bump "$@" ;;
        sync)    versions_sync "$@" ;;
        *)       cmd_versions_help ;;
    esac
}
