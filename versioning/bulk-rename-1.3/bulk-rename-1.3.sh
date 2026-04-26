#!/usr/bin/env bash
# bulk-rename — rename folders by exact name, optionally recursive
#
# Usage:
#   bulk-rename [OPTIONS] SOURCE TARGET [ROOT]
#
# Arguments:
#   SOURCE   Exact folder name to look for     (e.g. '!_test_folder')
#   TARGET   Name to rename matched folders to  (e.g. '[test_folder]')
#   ROOT     Where to search (default: current directory)
#
# Options:
#   -r, --recursive     Walk subdirectories (deepest-first, safe for nested paths)
#   -n, --dry-run       Print what would happen; make no changes
#   -v, --verbose       Print each rename as it happens (implied by --dry-run)
#   -o, --overwrite     If TARGET exists and contains conflicting filenames, overwrite them
#                       Without this flag, the script stops and reports the conflict
#   -h, --help          Show this help and exit

# Ver 1.3

set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

usage() {
    grep '^#' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

err()  { echo "[ERROR] $*" >&2; }
info() { echo "[INFO]  $*"; }
dry()  { echo "[DRY]   $*"; }

# ── argument parsing ──────────────────────────────────────────────────────────

RECURSIVE=false
DRY_RUN=false
VERBOSE=false
OVERWRITE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--recursive)  RECURSIVE=true;  shift ;;
        -n|--dry-run)    DRY_RUN=true;    shift ;;
        -v|--verbose)    VERBOSE=true;    shift ;;
        -o|--overwrite)  OVERWRITE=true;  shift ;;
        -h|--help)       usage 0 ;;
        --) shift; break ;;
        -*) err "Unknown option: $1"; usage 1 ;;
        *)  break ;;
    esac
done

[[ $# -lt 2 ]] && { err "Need SOURCE and TARGET arguments."; usage 1; }

SRC="$1"
TGT="$2"
SEARCH_ROOT="${3:-.}"

$DRY_RUN && VERBOSE=true

# ── helpers ───────────────────────────────────────────────────────────────────

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

# Merge SRC_DIR into DEST_DIR (rsync preferred, cp -a fallback).
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
            # Target folder already exists — check for filename conflicts before merging
            local conflict
            if ! conflict="$(find_conflict "$found_path" "$dest")"; then
                if $OVERWRITE; then
                    # Conflict exists but user asked for overwrite — proceed
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
                    err "Use -o / --overwrite to overwrite conflicting files."
                    exit 1
                fi
            else
                # No conflicts — safe to merge
                if $DRY_RUN; then
                    dry "MERGE (safe) '$found_path' → '$dest'"
                else
                    $VERBOSE && info "MERGE (safe) '$found_path' → '$dest'"
                    do_merge "$found_path" "$dest"
                fi
            fi
        else
            # No existing target — plain rename
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
