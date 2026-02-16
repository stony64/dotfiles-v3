#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        collect-review.sh
# VERSION:     3.6.10 (WINDOWS-FULL-FIX)
# DESCRIPTION: Dotfiles Aggregator for AI-Assisted Code Review
# AUTHOR:      Stony64
# CHANGES:     v3.6.10 - Complete Windows/Git Bash fix (pipes→for), glob, exclusions
# ------------------------------------------------------------------------------

# ShellCheck configuration
# SC2312: Consider invoking separately - Intentional command substitution chaining
# shellcheck disable=SC2312

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# --- CONFIGURATION ------------------------------------------------------------
# Script version (matches framework version for consistency)
readonly SCRIPT_VERSION="3.6.10"

# Project name (used in output filename)
readonly PROJECT_NAME="dotfiles"

# --- PARAMETER PARSING --------------------------------------------------------
# Target directory to scan (default: current directory)
TARGET_DIR=""

# Include all files regardless of exclusions (--all flag)
ALL_FILES=false

# Glob pattern for file inclusion filter (--include=pattern)
INCLUDE_PATTERN=""

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --all)
            ALL_FILES=true  # Disable exclusion filter
            ;;
        --include=*)
            # Extract pattern after '=' (e.g., --include=*.sh → *.sh)
            INCLUDE_PATTERN="${arg#*=}"
            ;;
        --help|-h)
            # Display usage information and exit
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
  $(basename "$0")                       # Scan current directory
  $(basename "$0") /opt/dotfiles         # Scan specific directory
  $(basename "$0") --include=".bash*"    # Only .bash* files (bashrc, bashenv)
  $(basename "$0") --include="*.sh"      # Only shell scripts
  $(basename "$0") --all                 # Include all files

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
            # Unknown option - show error and exit
            printf '\033[0;31mError: Unknown option: %s\033[0m\n' "$arg" >&2
            printf 'Use --help for usage information.\n' >&2
            exit 1
            ;;
        *)
            # Positional argument - treat as target directory
            [[ -z "$TARGET_DIR" ]] && TARGET_DIR="$arg"
            ;;
    esac
done

# Set default target directory to current working directory if not specified
TARGET_DIR="${TARGET_DIR:-$(pwd)}"

# --- VALIDATION ---------------------------------------------------------------
# Verify target directory exists (supports Windows paths via Git Bash)
if [[ ! -d "$TARGET_DIR" ]]; then
    printf '\033[0;31mError: Directory %s not found.\033[0m\n' "$TARGET_DIR" >&2
    exit 1
fi

# Create export directory in repository root
OUTPUT_DIR="${TARGET_DIR}/_exports"
mkdir -p "$OUTPUT_DIR" || {
    printf '\033[0;31mError: Failed to create output directory.\033[0m\n' >&2
    exit 1
}

# Generate filename with scope indicator and timestamp
# Scope indicates export mode: review (default), full-dump (--all), filtered (--include)
SCOPE="review"
[[ "$ALL_FILES" == true ]] && SCOPE="full-dump"
[[ -n "$INCLUDE_PATTERN" ]] && SCOPE="${SCOPE}-filtered"

# Timestamp format: YYYYMMDD_HHMMSS (sortable, filesystem-safe)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="${PROJECT_NAME}_${SCOPE}_${TIMESTAMP}.txt"
OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}"

# --- EXCLUSION CONFIGURATION --------------------------------------------------
# ✅ FIXED v3.6.10:
# - home/ REMOVED (blockierte .bashrc etc. aus home/)
# - collect-review.sh$, LICENSE$ → immer excluded (exact Dateiname-Ende)
# Regex pattern for files/directories to skip (unless --all is used)
# Excludes: Git internals, build artifacts, binaries, images, archives
readonly EXCLUDE_REGEX='/(\.git|_exports|node_modules|test_sandbox|bin|obj|\.vs|\.vscode|dist|build)/|(\.bak$|\.png$|\.jpg$|\.jpeg$|\.pdf$|\.ico$|\.zip$|\.tar\.gz$|LICENSE$|collect-review\.sh$|\.lock$)'

# --- STATISTICS TRACKING ------------------------------------------------------
# Counters for export statistics (displayed in footer)
declare -i total_files=0      # Files successfully exported
declare -i total_lines=0      # Total lines of code
declare -i skipped_files=0    # Files skipped by filters

# --- FILTER HELPER ------------------------------------------------------------
# ------------------------------------------------------------------------------
# ✅ FIXED v3.6.10: Native Bash Glob-Matching mit [[ ]]
# Bash [[ ]] behandelt rechte Seite unquoted als GLOB-Pattern
# Links quoted: Exakter Pfadvergleich
# Returns: 0=include, 1=skip
# Beispiele:
#   "home/.bashrc" == ".bash*"     → ✅ MATCH (bashrc endet mit bash)
#   "script.sh"    == "*.sh"       → ✅ MATCH
#   "home/xyz"     == "home/*"     → ✅ MATCH
# ------------------------------------------------------------------------------
should_include_file() {
    local file_path="$1"

    # No filter specified - include everything
    [[ -z "$INCLUDE_PATTERN" ]] && return 0

    # GLOB-MAGIC: Rechts unquoted → Bash Glob-Erweiterung aktiviert [web:40]
    # shellcheck disable=SC2053  # Intentional glob matching
    [[ "$file_path" == $INCLUDE_PATTERN ]]
  }

# --- EXPORT ENGINE ------------------------------------------------------------
# Main export block (redirect entire output to file)
{
    # Header with metadata for AI parsing
    echo "--- ${PROJECT_NAME^^} DUMP PROTOCOL V${SCRIPT_VERSION} ---"
    echo "METADATA | SOURCE: $TARGET_DIR | TIMESTAMP: $(date)"

    # Show active filters
    [[ -n "$INCLUDE_PATTERN" ]] && echo "FILTER | INCLUDE: $INCLUDE_PATTERN (glob pattern)"
    [[ "$ALL_FILES" == true ]] && echo "MODE | FULL DUMP (no exclusions)"
    echo "---------------------------------------------------------------------------"

    # ✅ v3.6.10 DEBUG: Zeigt gefundene Matches (nur bei --include)
    # Findet .bash*-Dateien vor Export-Filter
    [[ -n "$INCLUDE_PATTERN" ]] && {
        echo "DEBUG | Pattern search results (pre-filter):"
        find "$TARGET_DIR" -name "$INCLUDE_PATTERN" -type f 2>/dev/null | \
            sed 's/^/  /' | head -10 || echo "  (no matches found)"
        echo ""
    }

    # ------------------------------------------------------------------------------
    # ✅ CRITICAL FIX v3.6.10: Windows/Git Bash Pipe-Bug behoben
    # Ursache: find -print0 | sort -z | while read -d '' → Subshell → Schleife leer
    # Lösung: for file in $(find | sort) → Hauptprozess, Variablen persistent
    # Funktioniert: Git Bash, WSL, Linux, macOS
    # ------------------------------------------------------------------------------
    for file in $(find "$TARGET_DIR" -type f 2>/dev/null | sort); do

        # Calculate relative path (remove target directory prefix)
        rel_path="${file#"$TARGET_DIR"/}"

        # Apply exclusion filter (unless --all flag is set)
        if [[ "$ALL_FILES" != true && "/$rel_path" =~ $EXCLUDE_REGEX ]]; then
            ((skipped_files++)) || true  # || true prevents set -e abort
            continue
        fi

        # ✅ Include filter (glob-aware, Windows-safe)
        if ! should_include_file "$rel_path"; then
            ((skipped_files++)) || true
            continue
        fi

        # Extract file extension (everything after last dot)
        extension="${file##*.}"

        # Special handling for dotfiles without extension
        # Assign meaningful type based on filename patterns
        case "$rel_path" in
            *".bash"*) extension="bash" ;;
            *".gitattributes"*) extension="gitattributes" ;;
            *".gitignore"*) extension="gitignore" ;;
            ".shellcheckrc") extension="shellcheckrc" ;;
            ".editorconfig") extension="editorconfig" ;;
        esac

        # Count lines in file (handles binary files gracefully)
        line_count=$(wc -l < "$file" 2>/dev/null || echo "0")

        # Structured block header for AI parsing
        # Format: [FILE_START] path="..." type="..." lines=N
        echo "[FILE_START] path=\"$rel_path\" type=\".$extension\" lines=$line_count"
        echo "--- CONTENT START ---"

        # Output complete file content (preserves formatting)
        cat "$file"

        # Clean block close (ensure newline before footer)
        printf '\n--- CONTENT END ---\n'
        echo "[FILE_END] path=\"$rel_path\""
        echo "---------------------------------------------------------------------------"

        # Update statistics counters
        ((total_files++)) || true       # || true prevents set -e abort when count=0
        ((total_lines += line_count)) || true
    done

    # Statistics footer (summary of export)
    echo "--- STATISTICS ---"
    echo "Total Files:   $total_files"
    echo "Total Lines:   $total_lines"
    echo "Skipped Files: $skipped_files"
    echo "Export Time:   $(date)"
    echo "--- END OF DUMP ---"
} > "$OUTPUT_FILE"  # Redirect entire block to output file

# --- OUTPUT & INTEGRATION -----------------------------------------------------
# Display success message with color (green checkmark)
printf '\033[0;32m✓ Export successful: %s\033[0m\n' "$FILENAME"
printf '\033[0;36m  Format: v%s (Structured Framework Tag System)\033[0m\n' "$SCRIPT_VERSION"
printf '  Location: %s\n' "$OUTPUT_FILE"

# Show statistics inline
printf '  Files: %d | Lines: %d' "$total_files" "$total_lines"
[[ $skipped_files -gt 0 ]] && printf ' | Skipped: %d' "$skipped_files"
printf '\n'

# Display file size (human-readable format)
if command -v du >/dev/null 2>&1; then
    file_size=$(du -h "$OUTPUT_FILE" 2>/dev/null | cut -f1)
    printf '  Size: %s\n' "$file_size"
fi

# Clipboard integration (multi-platform support)
# Automatically copy content to clipboard if tool is available
if command -v clip.exe >/dev/null 2>&1; then
    # Windows (Git Bash/WSL) - uses native Windows clipboard
    clip.exe < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to Windows clipboard.\033[0m\n'
elif command -v xclip >/dev/null 2>&1; then
    # Linux X11 - requires xclip package (apt install xclip)
    xclip -selection clipboard < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to X11 clipboard.\033[0m\n'
elif command -v pbcopy >/dev/null 2>&1; then
    # macOS - native clipboard command
    pbcopy < "$OUTPUT_FILE"
    printf '\033[0;32m✓ Content copied to macOS clipboard.\033[0m\n'
fi

# Explorer integration (Windows/Git Bash/WSL only)
# Opens export directory in Windows Explorer for easy access
if command -v explorer.exe >/dev/null 2>&1; then
    # Convert Unix path to Windows path if needed (cygpath in Git Bash)
    explorer.exe "$(cygpath -w "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")"
fi
