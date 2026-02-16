#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        collect-review.sh
# VERSION:     3.6.7
# DESCRIPTION: Dotfiles Aggregator for AI-Assisted Code Review
# AUTHOR:      Stony64
# CHANGES:     v3.6.7 - Add --include filter, statistics, improved output
# ------------------------------------------------------------------------------
# Purpose: Creates structured dump with explicit metadata for AI code review.
# Usage:   bash collect-review.sh [target-dir] [--all] [--include pattern]
# Output:  _exports/dotfiles_review_TIMESTAMP.txt
# ------------------------------------------------------------------------------

# ShellCheck configuration
# shellcheck disable=SC2312

set -euo pipefail

# --- CONFIGURATION ------------------------------------------------------------
readonly SCRIPT_VERSION="3.6.7"
readonly PROJECT_NAME="dotfiles"

# --- PARAMETER PARSING --------------------------------------------------------
TARGET_DIR=""
ALL_FILES=false
INCLUDE_PATTERN=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --all)
            ALL_FILES=true
            ;;
        --include=*)
            INCLUDE_PATTERN="${arg#*=}"
            ;;
        --help|-h)
            cat <<EOF
Dotfiles Aggregator v${SCRIPT_VERSION}

Usage: $(basename "$0") [target-dir] [options]

Arguments:
  target-dir           Target directory to scan (default: current directory)

Options:
  --all                Include all files (ignore standard exclusions)
  --include=PATTERN    Only include files matching glob pattern (e.g., "*.sh")
  --help, -h           Show this help message

Examples:
  $(basename "$0")                           # Scan current directory
  $(basename "$0") /opt/dotfiles            # Scan specific directory
  $(basename "$0") --include="*.sh"         # Only shell scripts
  $(basename "$0") --include=".bash*"       # All bash dotfiles
  $(basename "$0") --all                    # Include all files

Pattern Examples:
  *.sh                 All .sh files
  .bash*               All .bash* files (bashrc, bashenv, etc.)
  home/*               All files in home/ directory
  *.{sh,bash}          All .sh and .bash files (brace expansion)

Output: _exports/${PROJECT_NAME}_review_TIMESTAMP.txt
EOF
            exit 0
            ;;
        -*)
            printf '\033[0;31mError: Unknown option: %s\033[0m\n' "$arg" >&2
            printf 'Use --help for usage information.\n' >&2
            exit 1
            ;;
        *)
            [[ -z "$TARGET_DIR" ]] && TARGET_DIR="$arg"
            ;;
    esac
done

# Set default target directory
TARGET_DIR="${TARGET_DIR:-$(pwd)}"

# --- VALIDATION ---------------------------------------------------------------
# Validate directory (supports Windows paths via Git Bash)
if [[ ! -d "$TARGET_DIR" ]]; then
    printf '\033[0;31mError: Directory %s not found.\033[0m\n' "$TARGET_DIR" >&2
    exit 1
fi

# Create export directory (repo root)
OUTPUT_DIR="${TARGET_DIR}/_exports"
mkdir -p "$OUTPUT_DIR" || {
    printf '\033[0;31mError: Failed to create output directory.\033[0m\n' >&2
    exit 1
}

# Generate filename with scope and timestamp
SCOPE="review"
[[ "$ALL_FILES" == true ]] && SCOPE="full-dump"
[[ -n "$INCLUDE_PATTERN" ]] && SCOPE="${SCOPE}-filtered"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${PROJECT_NAME}_${SCOPE}_${TIMESTAMP}.txt"
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}"

# --- EXCLUSION CONFIGURATION --------------------------------------------------
# Directories and file types to ignore (binaries, git internals, build artifacts)
readonly EXCLUDE_REGEX='/(\.git|_exports|node_modules|test_sandbox|bin|obj|\.vs|\.vscode|dist|build)/|(\.bak$|\.png$|\.jpg$|\.jpeg$|\.pdf$|\.ico$|\.zip$|\.tar\.gz$|LICENSE$|\.lock$)'

# --- STATISTICS TRACKING ------------------------------------------------------
declare -i total_files=0
declare -i total_lines=0
declare -i skipped_files=0

# --- FILTER HELPER ------------------------------------------------------------
# ------------------------------------------------------------------------------
# should_include_file
#
# Checks if file matches include pattern (if specified).
# Uses glob matching for pattern expansion (*.sh, .bash*, home/*, etc.).
#
# Parameters: $1 - File path
# Returns: 0 if should include, 1 if should skip
# ------------------------------------------------------------------------------
should_include_file() {
    local file_path="$1"

    # If no include pattern, include all
    [[ -z "$INCLUDE_PATTERN" ]] && return 0

    # Check if filename matches glob pattern
    # Note: $INCLUDE_PATTERN is intentionally unquoted to enable glob expansion
    # Examples: *.sh, .bash*, home/* - all require glob matching
    # shellcheck disable=SC2254
    case "$file_path" in
        $INCLUDE_PATTERN)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# --- EXPORT ENGINE ------------------------------------------------------------
{
    echo "--- ${PROJECT_NAME^^} DUMP PROTOCOL V${SCRIPT_VERSION} ---"
    echo "METADATA | SOURCE: $TARGET_DIR | TIMESTAMP: $(date)"
    [[ -n "$INCLUDE_PATTERN" ]] && echo "FILTER | INCLUDE: $INCLUDE_PATTERN (glob pattern)"
    [[ "$ALL_FILES" == true ]] && echo "MODE | FULL DUMP (no exclusions)"
    echo "---------------------------------------------------------------------------"

    # Null-terminated find for filenames with spaces; sorted output
    find "$TARGET_DIR" -type f -print0 2>/dev/null | sort -z | while IFS= read -r -d '' file; do

        # Calculate relative path
        rel_path="${file#"$TARGET_DIR"/}"

        # Apply exclusion filter (unless --all is set)
        if [[ "$ALL_FILES" != true && "/$rel_path" =~ $EXCLUDE_REGEX ]]; then
            ((skipped_files++)) || true
            continue
        fi

        # Apply include filter (if specified)
        # shellcheck disable=SC2310
        if ! should_include_file "$rel_path"; then
            ((skipped_files++)) || true
            continue
        fi

        # Extract file metadata
        extension="${file##*.}"

        # Special handling for dotfiles without extension
        case "$rel_path" in
            *".bash"*) extension="bash" ;;
            *".gitattributes"*) extension="gitattributes" ;;
            *".gitignore"*) extension="gitignore" ;;
            ".shellcheckrc") extension="shellcheckrc" ;;
            ".editorconfig") extension="editorconfig" ;;
        esac

        # Count lines (handle files without trailing newline)
        # SC2168 fix: No 'local' outside functions
        line_count=$(wc -l < "$file" 2>/dev/null || echo "0")

        # Structured block header for AI parsing
        echo "[FILE_START] path=\"$rel_path\" type=\".$extension\" lines=$line_count"
        echo "--- CONTENT START ---"

        # Output file content
        cat "$file"

        # Clean block close
        printf '\n--- CONTENT END ---\n'
        echo "[FILE_END] path=\"$rel_path\""
        echo "---------------------------------------------------------------------------"

        # Update statistics
        ((total_files++)) || true
        ((total_lines += line_count)) || true
    done

    # Statistics footer
    echo "--- STATISTICS ---"
    echo "Total Files:   $total_files"
    echo "Total Lines:   $total_lines"
    echo "Skipped Files: $skipped_files"
    echo "Export Time:   $(date)"
    echo "--- END OF DUMP ---"
} > "$OUTPUT_FILE"

# --- OUTPUT & INTEGRATION -----------------------------------------------------
printf '\033[0;32m✓ Export successful: %s\033[0m\n' "$FILENAME"
printf '\033[0;36m  Format: v%s (Structured Framework Tag System)\033[0m\n' "$SCRIPT_VERSION"
printf '  Location: %s\n' "$OUTPUT_FILE"
printf '  Files: %d | Lines: %d' "$total_files" "$total_lines"
[[ $skipped_files -gt 0 ]] && printf ' | Skipped: %d' "$skipped_files"
printf '\n'

# File size info
# SC2168 fix: No 'local' outside functions
if command -v du >/dev/null 2>&1; then
    file_size=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1)
    printf '  Size: %s\n' "$file_size"
fi

# Clipboard integration (Git Bash/WSL/Linux hybrid)
if command -v clip.exe >/dev/null 2>&1; then
    # Windows (Git Bash/WSL)
    clip.exe < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to Windows clipboard.\033[0m\n'
elif command -v xclip >/dev/null 2>&1; then
    # Linux X11
    xclip -selection clipboard < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to X11 clipboard.\033[0m\n'
elif command -v pbcopy >/dev/null 2>&1; then
    # macOS
    pbcopy < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to macOS clipboard.\033[0m\n'
fi

# Explorer integration (Windows/Git Bash/WSL only)
if command -v explorer.exe >/dev/null 2>&1; then
    explorer.exe "$(cygpath -w "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")"
fi
