#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:        dotfilesctl.sh
# VERSION:     3.6.9
# DESCRIPTION: Dotfiles Framework Controller
# AUTHOR:      Stony64
# LAST UPDATE: 2026-02-16
# CHANGES:     3.6.9 - ShellCheck compliant version
# --------------------------------------------------------------------------

set -euo pipefail

# --- BOOTSTRAP ----------------------------------------------------------------
SCRIPTDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
readonly SCRIPTDIR

if [[ ! -f "${SCRIPTDIR}/core.sh" ]]; then
    printf '\033[31m[FATAL]\033[0m core.sh not found\n' >&2
    exit 1
fi

source "${SCRIPTDIR}/core.sh" || exit 1

# --- CONFIGURATION ------------------------------------------------------------
readonly DOTFILES_DIR="${DF_REPO_ROOT:-${SCRIPTDIR}}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP

readonly BACKUP_DIR="${HOME}/.dotfiles_backups"

# --- HELPER FUNCTIONS ---------------------------------------------------------

show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Usage: $(basename "$0") <command> [options]

Commands:
  backup           Create timestamped backup of existing dotfiles
  install          Deploy dotfiles via symlinks
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

backup_dotfiles() {
    local backup_root="${BACKUP_DIR}"
    local timestamp="${TIMESTAMP}"
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

    # Files to backup
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
    local target
    for target in "${targets[@]}"; do
        if [[ -f "${HOME}/${target}" ]]; then
            if cp -L "${HOME}/${target}" "${current_backup_dir}/${target}" 2>/dev/null; then
                df_log_info "Backed up: ${target}"
                ((backed_up++)) || true
            else
                df_log_warn "Failed to copy: ${target}"
            fi
        fi
    done

    if [[ ${backed_up} -eq 0 ]]; then
        df_log_warn "No files found to backup."
        command rm -rf "${current_backup_dir}" 2>/dev/null || true
        return 0
    fi

    # Create tarball
    local backup_size
    if (cd "${backup_root}" && tar czf "backup-${timestamp}.tar.gz" "${timestamp}" 2>/dev/null); then
        command rm -rf "${current_backup_dir}"
        backup_size=$(du -sh "${backup_root}/backup-${timestamp}.tar.gz" 2>/dev/null | cut -f1)
        df_log_success "Backup created: backup-${timestamp}.tar.gz (${backed_up} files, ${backup_size})"
        return 0
    else
        df_log_error "Backup creation failed!"
        return 1
    fi
}

deploy_dotfiles() {
    local src_dir="${DOTFILES_DIR}/home"
    local timestamp="${TIMESTAMP}"
    local count=0
    local skipped=0

    df_log_info "Deploying from ${src_dir}..."

    if [[ ! -d "${src_dir}" ]]; then
        df_log_error "Directory not found: ${src_dir}"
        return 1
    fi

    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"

        # Skip directories
        if [[ -d "${src}" ]]; then
            continue
        fi

        # Skip backups
        if [[ "${filename}" == *.bak* ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        # Backup existing regular file
        if [[ -f "${dest}" && ! -L "${dest}" ]]; then
            local backup="${dest}.bak_${timestamp}"
            if mv "${dest}" "${backup}"; then
                df_log_warn "Backed up: ${filename} → $(basename "${backup}")"
            fi
        fi

        # Remove old symlink
        if [[ -L "${dest}" ]]; then
            command rm -f "${dest}" || true
        fi

        # Create new symlink
        if ln -sf "${src}" "${dest}"; then
            df_log_success "Linked: ${filename}"
            ((count++)) || true
        else
            df_log_error "Failed: ${filename}"
            ((skipped++)) || true
        fi
    done

    shopt -u dotglob nullglob || true

    printf '\n'
    df_log_success "Deployed ${count} files"
    if [[ ${skipped} -gt 0 ]]; then
        df_log_warn "Skipped ${skipped} files"
    fi
    return 0
}

remove_links() {
    local remove_backups=false
    local src_dir="${DOTFILES_DIR}/home"
    local count=0
    local backup_count=0

    if [[ "${1:-}" == "--backup" ]]; then
        remove_backups=true
    fi

    df_log_warn "Removing symlinks..."

    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"

        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        if [[ -L "${dest}" ]]; then
            if command rm -f "${dest}"; then
                df_log_info "Removed: ${filename}"
                ((count++)) || true
            fi
        fi

        # Remove backup files if requested
        if [[ "${remove_backups}" == true ]]; then
            local backup
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

    shopt -u dotglob nullglob || true

    printf '\n'
    df_log_success "Removed ${count} symlinks"
    if [[ ${backup_count} -gt 0 ]]; then
        df_log_success "Removed ${backup_count} backup files"
    fi

    # Warn about remaining backups
    if [[ "${remove_backups}" == false ]]; then
        local remaining
        remaining=$(find "${HOME}" -maxdepth 1 -name ".*.bak_*" 2>/dev/null | wc -l)
        if [[ ${remaining} -gt 0 ]]; then
            df_log_warn "${remaining} backup file(s) remain (use 'clean --backup' to remove)"
        fi
    fi

    return 0
}

check_status() {
    local src_dir="${DOTFILES_DIR}/home"
    local ok=0
    local err=0

    df_log_info "Status Check: ${src_dir} → ${HOME}"
    printf '\n'

    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"

        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/${filename}"

        if [[ -L "${dest}" ]]; then
            local target
            target=$(readlink "${dest}")
            if [[ "${target}" == "${src}" ]]; then
                df_log_success "${filename}"
                ((ok++)) || true
            else
                df_log_error "WRONG: ${filename} → ${target}"
                ((err++)) || true
            fi
        elif [[ -e "${dest}" ]]; then
            df_log_warn "BLOCKED: ${filename}"
            ((err++)) || true
        else
            df_log_error "MISSING: ${filename}"
            ((err++)) || true
        fi
    done

    shopt -u dotglob nullglob || true

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

case "${1:-help}" in
    backup)
        backup_dotfiles
        ;;

    install)
        df_log_info "Starting installation..."
        printf '\n'

        # Backup is optional
        set +e
        backup_dotfiles
        backup_exit=$?
        set -e

        if [[ ${backup_exit} -ne 0 ]]; then
            df_log_warn "Backup failed or no files found - continuing"
        fi

        printf '\n'
        deploy_dotfiles
        printf '\n'
        df_log_success "Done. Run: exec bash"
        ;;

    reinstall)
        df_log_warn "Reinstalling..."
        printf '\n'
        remove_links
        printf '\n'
        deploy_dotfiles
        printf '\n'
        df_log_success "Done. Run: exec bash"
        ;;

    status)
        check_status
        ;;

    clean)
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
        df_log_error "Unknown command: ${1}"
        printf '\n'
        show_usage
        exit 1
        ;;
esac
