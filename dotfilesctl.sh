#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:           dotfilesctl.sh
# VERSION:        3.7.0
# DESCRIPTION:    Dotfiles Framework Controller
# AUTHOR:         Stony64
# LAST UPDATE:    2026-03-01
# CHANGES:        3.7.0 - .nanorc als Copy (nicht Symlink) + erweiterte extra_configs
# --------------------------------------------------------------------------

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# --- BOOTSTRAP ----------------------------------------------------------------
# Resolve script directory (follows symlinks like /usr/local/bin/dctl -> dotfilesctl.sh)
SCRIPTDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
readonly SCRIPTDIR

# Check if core.sh exists
if [[ ! -f "${SCRIPTDIR}/core.sh" ]]; then
    printf '\033[31m[FATAL]\033[0m core.sh not found\n' >&2  # Red error to stderr
    exit 1
fi

# Load core framework (logging, colors, constants)
source "${SCRIPTDIR}/core.sh" || exit 1

# --- CONFIGURATION ------------------------------------------------------------
# Repository root directory (from core.sh or fallback to script dir)
readonly DOTFILES_DIR="${DF_REPO_ROOT:-${SCRIPTDIR}}"

# Timestamp for backup files (format: YYYYMMDD-HHMMSS)
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP

# Backup directory for dotfiles archives
readonly BACKUP_DIR="${HOME}/.dotfiles_backups"

# --- HELPER FUNCTIONS ---------------------------------------------------------

# Display framework version from core.sh constant
show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

# Display usage information and available commands
show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Usage: $(basename "$0") <command> [options]

Commands:
  backup           Create timestamped backup of existing dotfiles
  install          Deploy dotfiles via symlinks (+ copies for special files)
  reinstall        Remove existing links + redeploy
  status           Verify symlink integrity
  clean [--backup] Remove symlinks (--backup: also remove .bak_* files)
  version          Show framework version
  help             Show this help message

Examples:
  $(basename "$0") backup
  $(basename "$0") reinstall
  $(basename "$0") status
  $(basename "$0") clean --backup

Repository: ${DOTFILES_DIR}
EOF
}

# --- CORE FUNCTIONS -----------------------------------------------------------

# ------------------------------------------------------------------------------
# backup_dotfiles
#
# Creates timestamped tarball backup of existing dotfiles in $HOME.
# Backup is stored in ~/.dotfiles_backups/ as backup-YYYYMMDD-HHMMSS.tar.gz
#
# Returns: 0 on success, 1 on failure
# ------------------------------------------------------------------------------
backup_dotfiles() {
    local backup_root="${BACKUP_DIR}"
    local timestamp="${TIMESTAMP}"
    local current_backup_dir="${backup_root}/${timestamp}"

    # Verify tar is installed
    if ! command -v tar >/dev/null 2>&1; then
        df_log_error "tar not found - backup skipped (install: apt install tar)"
        return 1
    fi

    df_log_info "Creating backup in ${backup_root}..."

    # Create timestamped backup directory
    mkdir -p "${current_backup_dir}" || {
        df_log_error "Failed to create backup directory"
        return 1
    }

    # List of dotfiles to backup (add more as needed)
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
        ".vimrc"
        ".tmux.conf"
    )

    # Copy each existing file to backup directory
    local backed_up=0
    local target
    for target in "${targets[@]}"; do
        if [[ -f "${HOME}/${target}" ]]; then
            # Copy with -L to follow symlinks (backup actual file content)
            if cp -L "${HOME}/${target}" "${current_backup_dir}/${target}" 2>/dev/null; then
                df_log_info "Backed up: ${target}"
                ((backed_up++)) || true  # || true prevents set -e abort when count=0
            else
                df_log_warn "Failed to copy: ${target}"
            fi
        fi
    done

    # No files backed up - clean up and exit
    if [[ ${backed_up} -eq 0 ]]; then
        df_log_warn "No files found to backup."
        command rm -rf "${current_backup_dir}" 2>/dev/null || true  # command bypasses rm alias
        return 0
    fi

    # Create compressed tarball from backup directory
    local backup_size
    if (cd "${backup_root}" && tar czf "backup-${timestamp}.tar.gz" "${timestamp}" 2>/dev/null); then
        command rm -rf "${current_backup_dir}"  # Remove uncompressed directory
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
# Backs up existing regular files with .bak_TIMESTAMP suffix.
# Idempotent: Can be run multiple times safely.
# SKIPS .nanorc (handled by deploy_extra_configs as copy)
#
# Returns: 0 on success, 1 on failure
# ------------------------------------------------------------------------------
deploy_dotfiles() {
    local src_dir="${DOTFILES_DIR}/home"
    local timestamp="${TIMESTAMP}"
    local count=0
    local skipped=0

    df_log_info "Deploying from ${src_dir}..."

    # Verify source directory exists
    if [[ ! -d "${src_dir}" ]]; then
        df_log_error "Directory not found: ${src_dir}"
        return 1
    fi

    # Enable dotglob to match hidden files (.*), nullglob for empty matches
    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        # Extract filename (separate declaration for ShellCheck SC2155)
        local filename
        filename="$(basename "${src}")"

        # Skip directories (like config/)
        if [[ -d "${src}" ]]; then
            continue
        fi

        # Skip backup files (*.bak_*)
        if [[ "${filename}" == *.bak* ]]; then
            continue
        fi

        # SKIP .nanorc - handled as COPY in deploy_extra_configs
        if [[ "${filename}" == ".nanorc" ]]; then
            df_log_info "Skipped .nanorc (using copy method)"
            ((skipped++)) || true
            continue
        fi

        local dest="${HOME}/${filename}"

        # Backup existing regular file (not symlink)
        if [[ -f "${dest}" && ! -L "${dest}" ]]; then
            local backup="${dest}.bak_${timestamp}"
            if mv "${dest}" "${backup}"; then
                df_log_warn "Backed up: ${filename} → $(basename "${backup}")"
            fi
        fi

        # Remove old symlink if exists
        if [[ -L "${dest}" ]]; then
            command rm -f "${dest}" || true  # command bypasses rm alias, || true prevents abort
        fi

        # Create symlink from repository to home directory
        if ln -sf "${src}" "${dest}"; then
            df_log_success "Linked: ${filename}"
            ((count++)) || true  # || true prevents set -e abort when count=0
        else
            df_log_error "Failed: ${filename}"
            ((skipped++)) || true
        fi
    done

    # Restore shell options
    shopt -u dotglob nullglob || true

    # Print summary
    printf '\n'
    df_log_success "Deployed ${count} files"
    if [[ ${skipped} -gt 0 ]]; then
        df_log_warn "Skipped ${skipped} files"
    fi
    return 0
}

# ------------------------------------------------------------------------------
# deploy_extra_configs
#
# Copies configuration files for which symlinks must not be used.
# ENHANCED: .nanorc + full ~/.config/ copy (hard overwrite)
# ------------------------------------------------------------------------------
deploy_extra_configs() {
    local cfg_src_dir="${DOTFILES_DIR}/config"

    # .nanorc: Copy to ~ (not symlink - nano compatibility)
    if [[ -f "${cfg_src_dir}/nanorc" ]]; then
        # Backup existing .nanorc if regular file
        if [[ -f "${HOME}/.nanorc" && ! -L "${HOME}/.nanorc" ]]; then
            local backup="${HOME}/.nanorc.bak_${TIMESTAMP}"
            mv "${HOME}/.nanorc" "${backup}"
            df_log_warn "Backed up: .nanorc → $(basename "${backup}")"
        fi
        # Remove symlink if exists
        [[ -L "${HOME}/.nanorc" ]] && command rm -f "${HOME}/.nanorc"
        cp "${cfg_src_dir}/nanorc" "${HOME}/.nanorc"
        df_log_success "Copied .nanorc → ~/.nanorc"
    fi

    # mc: ~/.config/mc/ini
    if [[ -f "${cfg_src_dir}/mc/ini" ]]; then
        mkdir -p "${HOME}/.config/mc"
        cp "${cfg_src_dir}/mc/ini" "${HOME}/.config/mc/ini"
        df_log_success "Copied mc config to ~/.config/mc/ini"
    fi

    # micro: ~/.config/micro/*
    if [[ -d "${cfg_src_dir}/micro" ]]; then
        mkdir -p "${HOME}/.config/micro"
        # Force overwrite existing files
        cp -rf "${cfg_src_dir}/micro/." "${HOME}/.config/micro/"
        df_log_success "Copied micro config to ~/.config/micro/"
    fi

    # FULL ~/.config/ copy (all other configs - hard overwrite)
    if [[ -d "${cfg_src_dir}" ]]; then
        mkdir -p "${HOME}/.config"
        # Backup existing .config if needed? → No, hard overwrite per preference
        cp -rf "${cfg_src_dir}/." "${HOME}/.config/"
        df_log_success "Copied full config/ → ~/.config/ (hard overwrite)"
    fi
}

# ------------------------------------------------------------------------------
# remove_links
#
# Removes all symlinks pointing to repository from $HOME.
# Optionally removes .bak_* backup files if --backup flag is provided.
#
# Parameters: $1 - Optional: "--backup" to also remove backup files
# Returns: 0 on success
# ------------------------------------------------------------------------------
remove_links() {
    local remove_backups=false
    local src_dir="${DOTFILES_DIR}/home"
    local count=0
    local backup_count=0

    # Parse --backup flag
    if [[ "${1:-}" == "--backup" ]]; then
        remove_backups=true
    fi

    df_log_warn "Removing symlinks..."

    # Enable dotglob to match hidden files
    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        # Extract filename (separate declaration for ShellCheck SC2155)
        local filename
        filename="$(basename "${src}")"

        # Skip directories
        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        # Remove symlink if it exists
        if [[ -L "${dest}" ]]; then
            if command rm -f "${dest}"; then  # command bypasses rm alias
                df_log_info "Removed: ${filename}"
                ((count++)) || true  # || true prevents set -e abort
            fi
        fi

        # Remove backup files if requested
        if [[ "${remove_backups}" == true ]]; then
            local backup
            # Find all .bak_* files for this filename
            for backup in "${HOME}/${filename}".bak_*; do
                if [[ -e "${backup}" ]]; then
                    if command rm -f "${backup}"; then
                        df_log_info "Removed backup: $(basename "${backup}")"
                        ((backup_count++)) || true
                    fi
                fi
            done
        fi
    done

    # Restore shell options
    shopt -u dotglob nullglob || true

    # Print summary
    printf '\n'
    df_log_success "Removed ${count} symlinks"
    if [[ ${backup_count} -gt 0 ]]; then
        df_log_success "Removed ${backup_count} backup files"
    fi

    # Warn about remaining backup files
    if [[ "${remove_backups}" == false ]]; then
        local remaining
        remaining=$(find "${HOME}" -maxdepth 1 -name ".*.bak_*" 2>/dev/null | wc -l)
        if [[ ${remaining} -gt 0 ]]; then
            df_log_warn "${remaining} backup file(s) remain (use 'clean --backup' to remove)"
        fi
    fi

    return 0
}

# ------------------------------------------------------------------------------
# check_status
#
# Verifies integrity of symlinks from repository to $HOME.
# Reports status for each file: OK/WRONG/MISSING/BLOCKED.
# .nanorc: Special check for copy (FILE, not symlink)
#
# Returns: 0 if all clean, 1 if issues found
# ------------------------------------------------------------------------------
check_status() {
    local src_dir="${DOTFILES_DIR}/home"
    local ok=0
    local err=0

    df_log_info "Status Check: ${src_dir} → ${HOME}"
    printf '\n'

    # Enable dotglob to match hidden files
    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        # Extract filename (separate declaration for ShellCheck SC2155)
        local filename
        filename="$(basename "${src}")"

        # Skip directories
        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        # Special handling for .nanorc (should be FILE, not symlink)
        if [[ "${filename}" == ".nanorc" ]]; then
            if [[ -f "${dest}" && ! -L "${dest}" ]]; then
                df_log_success "${filename} (copy OK)"
                ((ok++)) || true
            else
                df_log_error "${filename}: MISSING or WRONG (expect FILE)"
                ((err++)) || true
            fi
            continue
        fi

        # Check symlink status for others
        if [[ -L "${dest}" ]]; then
            # Symlink exists - verify it points to repository
            local target
            target=$(readlink "${dest}")
            if [[ "${target}" == "${src}" ]]; then
                df_log_success "${filename}"  # Correct symlink
                ((ok++)) || true
            else
                df_log_error "WRONG: ${filename} → ${target}"  # Points elsewhere
                ((err++)) || true
            fi
        elif [[ -e "${dest}" ]]; then
            df_log_warn "BLOCKED: ${filename}"  # Regular file exists
            ((err++)) || true
        else
            df_log_error "MISSING: ${filename}"  # Should exist but doesn't
            ((err++)) || true
        fi
    done

    # Restore shell options
    shopt -u dotglob nullglob || true

    # Print summary
    printf '\n'
    if [[ ${err} -eq 0 ]]; then
        df_log_success "All ${ok} links OK"
        return 0
    else
        df_log_error "${err} issues, ${ok} OK"
        return 1
    fi
}

# --- MAIN EXECUTION -----------------------------------------------------------

# Command dispatcher (default: help)
case "${1:-help}" in
    backup)
        backup_dotfiles
        ;;

    install)
        df_log_info "Starting installation..."
        printf '\n'

        # Try to create backup (optional - don't fail if unsuccessful)
        set +e  # Temporarily disable exit on error
        backup_dotfiles
        backup_exit=$?
        set -e  # Re-enable exit on error

        # Warn if backup failed but continue anyway
        if [[ ${backup_exit} -ne 0 ]]; then
            df_log_warn "Backup failed or no files found - continuing"
        fi

        # Deploy dotfiles
        printf '\n'
        deploy_dotfiles
        deploy_extra_configs
        printf '\n'
        df_log_success "Done. Run: exec bash"
        ;;

    reinstall)
        df_log_warn "Reinstalling..."
        printf '\n'

        # Remove existing symlinks
        remove_links
        printf '\n'

        # Deploy fresh symlinks
        deploy_dotfiles
        deploy_extra_configs
        printf '\n'
        df_log_success "Done. Run: exec bash"
        ;;

    status)
        check_status
        ;;

    clean)
        # Parse optional --backup flag
        if [[ "${2:-}" == "--backup" ]]; then
            remove_links --backup  # Remove symlinks AND backup files
        else
            remove_links  # Remove symlinks only
        fi
        ;;

    version)
        show_version
        ;;

    help|--help|-h)
        show_usage
        ;;

    *)
        # Unknown command - show error and usage
        df_log_error "Unknown command: ${1}"
        printf '\n'
        show_usage
        exit 1
        ;;
esac
