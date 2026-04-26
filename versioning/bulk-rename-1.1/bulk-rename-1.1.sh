#!/usr/bin/env bash
# bulk-rename — rename folders by exact name, optionally recursive
#
# Usage:
#   bulk-rename [OPTIONS] SOURCE TARGET [ROOT]
#
# Arguments:
#   SOURCE   Exact folder name to look for      (e.g. '!_test_folder')
#   TARGET   Name to rename matched folders to   (e.g. '[test_folder]')
#   ROOT     Where to search (default: current directory)
#
# Options:
#   -r   Recursive — walk subdirectories (deepest-first, safe for nested paths)
#   -n   Dry run  — print what would happen; make no changes
#   -v   Verbose  — print each rename as it happens (implied by -n)
#   -o   Overwrite — if TARGET exists with conflicting filenames, overwrite them
#                    Without this flag the script stops and reports the conflict
#   -h   Show this help and exit
#
# Flags can be combined in any order: -rnv, -rno, -nr, etc.
#
# NOTE: Always use single quotes around arguments containing shell-special
#       characters like !, [, ], *, ?
#       CORRECT:   bulk-rename -rn '!_test_folder' '[test_folder]'
#       INCORRECT: bulk-rename -rn "!_test_folder" "[test_folder]"

# Ver 1.1

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

err()  { echo "[ERROR] $*" >&2; }
info() { echo "[INFO]  $*"; }
dry()  { echo "[DRY]   $*"; }

# ── argument parsing (getopts — supports combined flags like -rno) ─────────────

RECURSIVE=false
DRY_RUN=false
VERBOSE=false
OVERWRITE=false

while getopts ":rnvoh" opt; do
    case "$opt" in
        r) RECURSIVE=true  ;;
        n) DRY_RUN=true    ;;
        v) VERBOSE=true    ;;
        o) OVERWRITE=true  ;;
        h) usage 0         ;;
        :) err "Option -$OPTARG requires an argument."; usage 1 ;;
        ?) err "Unknown option: -$OPTARG"; usage 1 ;;
    esac
done
shift $(( OPTIND - 1 ))

[[ $# -lt 2 ]] && { err "Need SOURCE and TARGET arguments."; usage 1; }

SRC="$1"
TGT="$2"
SEARCH_ROOT="${3:-.}"

$DRY_RUN && VERBOSE=true

# ── conflict check ────────────────────────────────────────────────────────────

# Prints the first conflicting filename if merging SRC_DIR into DEST_DIR
# would clobber anything; returns 1 if a conflict is found.
find_conflict() {
    local src_dir="$1"
    local dest_dir="$2"

    while IFS= read -r -d '' item; do
        local name
        name="$(basename "$item")"
        if [[ -e "${dest_dir}/${name}" ]]; then
            echo "$name"
            return 1
        fi
    done < <(find "$src_dir" -maxdepth 1 -mindepth 1 -print0)

    return 0
}

# ── merge ─────────────────────────────────────────────────────────────────────

do_merge() {
    local src_dir="$1"
    local dest_dir="$2"

    if command -v rsync &>/dev/null; then
        rsync -a --remove-source-files "$src_dir"/ "$dest_dir"/
        find "$src_dir" -depth -type d -empty -delete 2>/dev/null || true
    else
        cp -a "$src_dir"/. "$dest_dir"/
        rm -rf "$src_dir"
    fi
}

# ── core loop ─────────────────────────────────────────────────────────────────

main() {
    local count=0
    local find_args=( find "$SEARCH_ROOT" -depth -type d -name "$SRC" )
    $RECURSIVE || find_args+=( -maxdepth 1 )

    while IFS= read -r -d '' found_path; do
        local parent dest
        parent="$(dirname "$found_path")"
        dest="${parent}/${TGT}"

        if [[ -e "$dest" ]]; then
            local conflict
            if ! conflict="$(find_conflict "$found_path" "$dest")"; then
                if $OVERWRITE; then
                    if $DRY_RUN; then
                        dry "MERGE (overwrite '$conflict' and others) '$found_path' → '$dest'"
                    else
                        $VERBOSE && info "MERGE (overwrite) '$found_path' → '$dest'"
                        do_merge "$found_path" "$dest"
                    fi
                else
                    err "Conflicting filename: '$conflict'"
                    err "  Source: '$found_path'"
                    err "  Target: '$dest'"
                    err "Use -o to overwrite conflicting files."
                    exit 1
                fi
            else
                if $DRY_RUN; then
                    dry "MERGE (safe) '$found_path' → '$dest'"
                else
                    $VERBOSE && info "MERGE (safe) '$found_path' → '$dest'"
                    do_merge "$found_path" "$dest"
                fi
            fi
        else
            if $DRY_RUN; then
                dry "RENAME '$found_path' → '$dest'"
            else
                $VERBOSE && info "RENAME '$found_path' → '$dest'"
                mv -- "$found_path" "$dest"
            fi
        fi

        (( count++ )) || true
    done < <("${find_args[@]}" -print0 2>/dev/null)

    info "Done: ${count} folders processed."
}

# ── entry point ───────────────────────────────────────────────────────────────

$DRY_RUN && info "DRY RUN — no changes will be made."
info "Root:      $(realpath "$SEARCH_ROOT")"
info "Source:    '$SRC'"
info "Target:    '$TGT'"
info "Recursive: $RECURSIVE"
echo

main
