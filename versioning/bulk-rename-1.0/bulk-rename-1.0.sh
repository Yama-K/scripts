#!/usr/bin/env bash
# bulk-rename — rename folders by exact name, optionally recursive
# Usage:
#   bulk-rename [OPTIONS] SOURCE TARGET
#   bulk-rename [OPTIONS] SOURCE1,SOURCE2,... TARGET1,TARGET2,...
#
# Options:
#   -r, --recursive     Walk subdirectories (deepest-first, safe for nested paths)
#   -n, --dry-run       Print what would happen; make no changes
#   -v, --verbose       Print each rename as it happens (implied by --dry-run)
#   -f, --force         If TARGET exists, merge contents into it; without this flag,
#                       existing targets cause a skip (with a warning)
#   -h, --help          Show this help

# Ver 1.0
set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
    sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \{0,1\}//; p }' "$0"
    exit "${1:-0}"
}

err()  { echo "[ERROR] $*" >&2; }
warn() { echo "[WARN]  $*" >&2; }
info() { echo "[INFO]  $*"; }
dry()  { echo "[DRY]   $*"; }

# ── argument parsing ──────────────────────────────────────────────────────────

RECURSIVE=false
DRY_RUN=false
VERBOSE=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--recursive) RECURSIVE=true;  shift ;;
        -n|--dry-run)   DRY_RUN=true;    shift ;;
        -v|--verbose)   VERBOSE=true;    shift ;;
        -f|--force)     FORCE=true;      shift ;;
        -h|--help)      usage 0 ;;
        --) shift; break ;;
        -*) err "Unknown option: $1"; usage 1 ;;
        *)  break ;;
    esac
done

[[ $# -lt 2 ]] && { err "Need at least SOURCE and TARGET arguments."; usage 1; }

SOURCES_RAW="$1"
TARGETS_RAW="$2"

# Split comma-separated lists
IFS=',' read -r -a SOURCES <<< "$SOURCES_RAW"
IFS=',' read -r -a TARGETS <<< "$TARGETS_RAW"

# Validate counts match
if [[ ${#SOURCES[@]} -ne ${#TARGETS[@]} ]]; then
    err "Source count (${#SOURCES[@]}) does not match target count (${#TARGETS[@]})."
    err "  Sources: ${SOURCES[*]}"
    err "  Targets: ${TARGETS[*]}"
    exit 1
fi

$DRY_RUN && VERBOSE=true

# ── core rename logic ─────────────────────────────────────────────────────────

# do_rename SOURCE_NAME TARGET_NAME SEARCH_ROOT
# Finds all directories named SOURCE_NAME under SEARCH_ROOT and renames them.
do_rename() {
    local src="$1"
    local tgt="$2"
    local root="$3"
    local count=0
    local skipped=0

    # Build find command
    # -depth ensures children are processed before parents — critical for nested matches
    local find_args=( find "$root" -depth -type d -name "$src" )
    $RECURSIVE || find_args+=( -maxdepth 1 )

    while IFS= read -r -d '' found_path; do
        local parent
        parent="$(dirname "$found_path")"
        local dest="${parent}/${tgt}"

        if [[ -e "$dest" ]]; then
            if $FORCE; then
                # Merge: move contents of found_path into dest, then remove found_path
                if $DRY_RUN; then
                    dry "MERGE  '$found_path' → '$dest' (contents merged)"
                else
                    $VERBOSE && info "MERGE  '$found_path' → '$dest'"
                    # Move each item; rsync would be safer for large trees but adds a dependency
                    if command -v rsync &>/dev/null; then
                        rsync -a --remove-source-files "$found_path"/ "$dest"/
                        # Remove now-empty dirs left behind by rsync
                        find "$found_path" -depth -type d -empty -delete 2>/dev/null || true
                    else
                        # Fallback: cp -a then rm
                        cp -a "$found_path"/. "$dest"/
                        rm -rf "$found_path"
                    fi
                fi
            else
                warn "SKIP   '$found_path' — target '$dest' already exists (use -f to merge)"
                (( skipped++ )) || true
                continue
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

    info "  '$src' → '$tgt': ${count} renamed, ${skipped} skipped"
}

# ── main ──────────────────────────────────────────────────────────────────────

SEARCH_ROOT="${3:-.}"   # optional 3rd arg = search root; defaults to cwd

$DRY_RUN && info "DRY RUN — no changes will be made."
info "Search root: $(realpath "$SEARCH_ROOT")"
info "Recursive:   $RECURSIVE"
echo

for i in "${!SOURCES[@]}"; do
    src="${SOURCES[$i]}"
    tgt="${TARGETS[$i]}"
    info "Processing: '$src' → '$tgt'"
    do_rename "$src" "$tgt" "$SEARCH_ROOT"
done

echo
info "Done."
