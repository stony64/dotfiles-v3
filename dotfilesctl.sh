#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:        dotfilesctl.sh
# VERSION:     3.6.7
# DESCRIPTION: Dotfiles Framework Controller
# AUTHOR:      Stony64
# LAST UPDATE: 2026-02-16
# CHANGES:     3.6.7 - Fix set -e compatibility with && continue patterns
# --------------------------------------------------------------------------

set -euo pipefail

# --- BOOTSTRAP: RESOLVE SCRIPT DIRECTORY --------------------------------------
# Handle symlinks correctly (e.g., /usr/local/bin/dctl -> /opt/dotfiles/dotfilesctl.sh)
# shellcheck disable=SC2128
SCRIPTDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
readonly SCRIPTDIR

# --- BOOTSTRAP: LOAD CORE FRAMEWORK -------------------------------------------
if [[ ! -f "${SCRIPTDIR}/core.sh" ]]; then
    printf '\033[31m[FATAL]\033[0m core.sh not found\n' >&2
    printf 'Expected: %s/core.sh\n' "${SCRIPTDIR}" >&2
    printf 'SCRIPTDIR: %s\n' "${SCRIPTDIR}" >&2
    exit 1
fi

if ! source "${SCRIPTDIR}/core.sh"; then
    printf '\033[31m[FATAL]\033[0m Failed to load core.sh\n' >&2
    exit 1
fi
# shellcheck source=core.sh

# --- CONFIGURATION ------------------------------------------------------------
readonly DOTFILES_DIR="${DF_REPO_ROOT:-${SCRIPTDIR}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP
readonly BACKUP_DIR="${HOME}/.dotfiles_backups"

# --- HELPER FUNCTIONS ---------------------------------------------------------

# ------------------------------------------------------------------------------
# show_version
#
# Displays framework version from core.sh.
#
# Parameters: None
# Returns: None
# ------------------------------------------------------------------------------
show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

# ------------------------------------------------------------------------------
# show_usage
#
# Displays usage information and available commands.
#
# Parameters: None
# Returns: None
# ------------------------------------------------------------------------------
show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Usage: $(basename "$0") <command> [options]

Commands:
  backup           Create timestamped backup of existing dotfiles
  install          Backup existing files + deploy framework via symlinks
  reinstall        Remove existing links + redeploy (clean slate)
  status           Verify symlink integrity (OK/WRONG/MISSING/FILE)
  clean [--backup] Remove symlinks (--backup: also remove .bak_* files)
  version          Show framework version
  help             Show this help message

Examples:
  $(basename "$0") status
  $(basename "$0") backup
  $(basename "$0") reinstall
  $(basename "$0") clean --backup

Repository: ${DOTFILES_DIR}
EOF
}

# ------------------------------------------------------------------------------
# show_status_legend
#
# Displays color-coded legend for status check output.
#
# Parameters: None
# Returns: None
# ------------------------------------------------------------------------------
show_status_legend() {
    cat <<EOF
Status Legend:
  ${DF_C_GREEN}[OK]${DF_C_RESET}      Symlink correct (points to repository)
  ${DF_C_RED}[ERR]${DF_C_RESET}     WRONG target (symlink points elsewhere)
  ${DF_C_RED}[ERR]${DF_C_RESET}     MISSING (symlink should exist but doesn't)
  ${DF_C_YELLOW}[! ]${DF_C_RESET}     BLOCKED (regular file exists, preventing symlink)

EOF
}

# --- CORE FUNCTIONS -----------------------------------------------------------

# ------------------------------------------------------------------------------
# backup_dotfiles
#
# Creates timestamped backup of existing dotfiles in $HOME.
# Creates tarball in $BACKUP_DIR, removes temporary directory after compression.
# Uses subshell for cd to maintain working directory.
# Checks for tar availability before attempting backup.
#
# Parameters: None
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
backup_dotfiles() {
    local backup_root="${BACKUP_DIR:?}"
    local timestamp="${TIMESTAMP:?}"
    local current_backup_dir="${backup_root}/${timestamp}"

    # Check if tar is available
    if ! command -v tar >/dev/null 2>&1; then
        df_log_error "tar not found - backup skipped (install: apt install tar)"
        return 1
    fi

    df_log_info "Creating backup in ${backup_root}..."
    mkdir -p "${current_backup_dir}" || {
        df_log_error "Failed to create backup directory"
        return 1
    }

    # Files to backup (comprehensive list)
    local targets=(
        ".bashrc"
        ".bash_profile"
        ".bashenv"
        ".bashaliases"
        ".bashfunctions"
        ".bashprompt"
        ".bashwartung"
        ".dircolors"
        ".nanorc"
        ".gitconfig"
        ".vimrc"
        ".tmux.conf"
    )

    local backed_up=0
    for target in "${targets[@]}"; do
        if [[ -f "${HOME}/${target}" ]]; then
            if cp -L "${HOME}/${target}" "${current_backup_dir}/${target}" 2>/dev/null; then
                df_log_info "Backed up: ${target}"
                ((backed_up++))
            else
                df_log_warn "Failed to copy: ${target}"
            fi
        fi
    done

    if [[ ${backed_up} -eq 0 ]]; then
        df_log_warn "No files found to backup."
        rmdir "${current_backup_dir}" 2>/dev/null || true
        return 0
    fi

    # Use subshell for cd to maintain working directory
    if (cd "${backup_root}" && tar czf "backup-${timestamp}.tar.gz" "${timestamp}" 2>/dev/null); then
        rm -rf "${current_backup_dir}"
        local backup_size
        backup_size=$(du -sh "${backup_root}/backup-${timestamp}.tar.gz" 2>/dev/null | cut -f1)
        df_log_success "Backup created: backup-${timestamp}.tar.gz (${backed_up} files, ${backup_size})"
        return 0
    else
        df_log_error "Backup creation failed!"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# deploy_dotfiles
#
# Deploys dotfiles from repository to $HOME via symlinks.
# Backs up existing files with timestamp suffix.
# Idempotent: Can be run multiple times safely.
#
# Parameters: None
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
deploy_dotfiles() {
    local src_dir="${DOTFILES_DIR}/home"
    local timestamp="${TIMESTAMP:?}"
    local deployed_count=0
    local skipped_count=0

    df_log_info "Deploying dotfiles from ${src_dir}..."

    if [[ ! -d "${src_dir}" ]]; then
        df_log_error "Source directory '${src_dir}' does not exist!"
        return 1
    fi

    # Enable dotglob to match hidden files
    shopt -s dotglob nullglob

    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"

        # Skip backup files - USE IF instead of && to avoid set -e issues
        if [[ "${filename}" == *.bak* ]]; then
            continue
        fi

        # Skip directories - USE IF instead of && to avoid set -e issues
        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        # Backup existing file (not link)
        if [[ -e "${dest}" && ! -L "${dest}" ]]; then
            local backup_name="${dest}.bak_${timestamp}"
            if mv "${dest}" "${backup_name}" 2>/dev/null; then
                df_log_warn "Backed up existing: ${filename} → $(basename "${backup_name}")"
            else
                df_log_error "Failed to backup: ${filename}"
                ((skipped_count++))
                continue
            fi
        fi

        # Remove old symlink if exists
        if [[ -L "${dest}" ]]; then
            rm -f "${dest}"
        fi

        # Create symlink (removed -n flag for better compatibility)
        if ln -sf "${src}" "${dest}" 2>/dev/null; then
            df_log_success "Linked: ${filename}"
            ((deployed_count++))
        else
            df_log_error "Failed to link: ${filename}"
            ((skipped_count++))
        fi
    done

    shopt -u dotglob nullglob

    # Summary
    echo ""
    df_log_success "Deployment complete: ${deployed_count} files linked"
    if [[ ${skipped_count} -gt 0 ]]; then
        df_log_warn "Skipped: ${skipped_count} files"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# check_status
#
# Verifies integrity of symlinks from repository to $HOME.
# Reports status for each file: OK/WRONG/MISSING/BLOCKED.
# Displays color-coded legend at the beginning.
#
# Parameters: None
# Returns: 0 if all clean, error count otherwise
# ------------------------------------------------------------------------------
check_status() {
    local ok_count=0
    local error_count=0
    local target_dir="${HOME}"
    local source_dir="${DOTFILES_DIR}/home"

    df_log_info "Integrity check: Repo → ${target_dir}"
    echo ""

    # Show legend
    show_status_legend

    shopt -s dotglob nullglob
    for source in "${source_dir}"/*; do
        local filename
        filename="$(basename "${source}")"

        # Skip directories (like .config) - USE IF instead of && to avoid set -e issues
        if [[ -d "${source}" ]]; then
            continue
        fi

        local target_file="${target_dir}/${filename}"

        if [[ -L "${target_file}" ]]; then
            local link_target
            link_target=$(readlink "${target_file}")
            if [[ "${link_target}" == "${source}" ]]; then
                df_log_success "${filename}"
                ((ok_count++))
            else
                df_log_error "WRONG: ${filename} → ${link_target}"
                ((error_count++))
            fi
        elif [[ -e "${target_file}" ]]; then
            df_log_warn "BLOCKED: ${filename} (regular file exists)"
            ((error_count++))
        else
            df_log_error "MISSING: ${filename}"
            ((error_count++))
        fi
    done
    shopt -u dotglob nullglob

    echo ""
    if [[ ${error_count} -eq 0 ]]; then
        df_log_success "Status: All ${ok_count} links OK"
        return 0
    else
        df_log_error "Status: ${error_count} issue(s) found, ${ok_count} OK"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# remove_links
#
# Removes all symlinks pointing to repository from $HOME.
# Optionally removes .bak_* backup files if --backup flag is set.
# Used for clean reinstall or cleanup.
#
# Parameters: $1 - Optional: "--backup" to also remove backup files
# Returns: None
# ------------------------------------------------------------------------------
remove_links() {
    local remove_backups=false
    local removed_links=0
    local removed_backups=0

    if [[ "${1:-}" == "--backup" ]]; then
        remove_backups=true
    fi

    df_log_warn "Removing existing symlinks..."

    shopt -s dotglob nullglob
    for src in "${DOTFILES_DIR}/home"/*; do
        local filename
        filename="$(basename "${src}")"
        local target="${HOME}/${filename}"

        # Remove symlink if it exists
        if [[ -L "${target}" ]]; then
            if rm "${target}" 2>/dev/null; then
                df_log_info "Removed link: ${filename}"
                ((removed_links++))
            else
                df_log_warn "Failed to remove link: ${filename}"
            fi
        fi

        # Remove backup files if requested
        if [[ "${remove_backups}" == true ]]; then
            # Find all .bak_* files for this filename
            for backup in "${HOME}/${filename}".bak_*; do
                if [[ -e "${backup}" ]]; then
                    if rm "${backup}" 2>/dev/null; then
                        df_log_info "Removed backup: $(basename "${backup}")"
                        ((removed_backups++))
                    else
                        df_log_warn "Failed to remove backup: $(basename "${backup}")"
                    fi
                fi
            done
        fi
    done
    shopt -u dotglob nullglob

    # Summary
    echo ""
    df_log_success "Removed: ${removed_links} symlinks"
    if [[ ${removed_backups} -gt 0 ]]; then
        df_log_success "Removed: ${removed_backups} backup files"
    fi

    # Warn about remaining backups if not removed
    if [[ "${remove_backups}" == false ]]; then
        local backup_count
        backup_count=$(find "${HOME}" -maxdepth 1 -name ".*.bak_*" 2>/dev/null | wc -l)
        if [[ ${backup_count} -gt 0 ]]; then
            df_log_warn "${backup_count} backup file(s) remain (use 'clean --backup' to remove)"
        fi
    fi
}

# --- MAIN EXECUTION -----------------------------------------------------------

case "${1:-help}" in
    backup)
        backup_dotfiles
        ;;

    install)
        df_log_info "Starting installation..."

        # Backup is optional - errors won't stop installation
        set +e
        backup_dotfiles
        backup_exit_code=$?
        set -e

        if [[ ${backup_exit_code} -ne 0 ]]; then
            df_log_warn "Backup failed or no files found - continuing with installation"
        fi

        deploy_dotfiles
        echo ""
        df_log_success "Installation complete. Run 'source ~/.bashrc' to activate."
        ;;

    reinstall)
        df_log_warn "Reinstalling (removing existing links)..."
        remove_links
        echo ""
        deploy_dotfiles
        echo ""
        df_log_success "Reinstallation complete. Run 'source ~/.bashrc' to activate."
        ;;

    status)
        check_status
        ;;

    clean)
        # Parse --backup flag
        if [[ "${2:-}" == "--backup" ]]; then
            remove_links --backup
        else
            remove_links
        fi
        ;;

    version)
        show_version
        ;;

    help|--help|-h)
        show_usage
        ;;

    *)
        df_log_error "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac
