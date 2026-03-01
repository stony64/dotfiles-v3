#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:           dotfilesctl.sh
# VERSION:        3.8.0
# DESCRIPTION:    Dotfiles Framework Controller
# AUTHOR:         Stony64
# LAST UPDATE:    2026-03-01
# CHANGES:        3.8.0 - Multi-User, .nanorc copy (home/), ~/.config/ copy
# --------------------------------------------------------------------------

# Exit on error, undefined variables, pipe failures
set -euo pipefail

# --- BOOTSTRAP ----------------------------------------------------------------
# Resolve script directory
SCRIPTDIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")
readonly SCRIPTDIR

# Check if core.sh exists
if [[ ! -f "${SCRIPTDIR}/core.sh" ]]; then
    printf '\033[31m[FATAL]\033[0m core.sh not found\n' >&2
    exit 1
fi

# Load core framework
source "${SCRIPTDIR}/core.sh" || exit 1

# --- CONFIGURATION ------------------------------------------------------------
readonly DOTFILES_DIR="${DF_REPO_ROOT:-${SCRIPTDIR}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly TIMESTAMP

# --- HELPER FUNCTIONS ---------------------------------------------------------
show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Usage: $(basename "$0") <command> [options]

Commands:
  backup           Create timestamped backup
  install [--all]  Deploy dotfiles (--all: for all real users)
  reinstall        Remove existing links + redeploy
  status           Verify symlink integrity
  clean [--backup] Remove symlinks (--backup: also remove backups)
  version          Show framework version
  help             Show this help message

Examples:
  sudo $(basename "$0") install --all
  $(basename "$0") reinstall
  $(basename "$0") status
EOF
}

# --- CORE FUNCTIONS -----------------------------------------------------------

backup_dotfiles() {
    local backup_root="${HOME}/.dotfiles_backups"
    local timestamp="${TIMESTAMP}"
    local current_backup_dir="${backup_root}/${timestamp}"

    if ! command -v tar >/dev/null 2>&1; then
        df_log_error "tar not found - backup skipped"
        return 1
    fi

    df_log_info "Creating backup in ${backup_root}..."
    mkdir -p "${current_backup_dir}" || return 1

    local targets=(
        ".bashrc" ".bash_profile" ".bashenv" ".bashaliases"
        ".bashfunctions" ".bashprompt" ".bashwartung"
        ".dircolors" ".nanorc" ".vimrc" ".tmux.conf"
    )

    local backed_up=0
    local target
    for target in "${targets[@]}"; do
        if [[ -f "${HOME}/${target}" ]]; then
            if cp -L "${HOME}/${target}" "${current_backup_dir}/${target}" 2>/dev/null; then
                df_log_info "Backed up: ${target}"
                ((backed_up++)) || true
            fi
        fi
    done

    if [[ ${backed_up} -eq 0 ]]; then
        df_log_warn "No files found to backup."
        command rm -rf "${current_backup_dir}" 2>/dev/null || true
        return 0
    fi

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

        # Skip directories and backups
        if [[ -d "${src}" ]] || [[ "${filename}" == *.bak* ]]; then
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

        # Create symlink
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
    [[ ${skipped} -gt 0 ]] && df_log_warn "Skipped ${skipped} files"
    return 0
}

deploy_extra_configs() {
    local home_dir="${DOTFILES_DIR}/home"
    local cfg_src_dir="${home_dir}/config"

    # .nanorc: Priority home/ (flat)
    local nanorc_src="${home_dir}/.nanorc"
    if [[ -f "${nanorc_src}" ]]; then
        if [[ -f "${HOME}/.nanorc" && ! -L "${HOME}/.nanorc" ]]; then
            mv "${HOME}/.nanorc" "${HOME}/.nanorc.bak_${TIMESTAMP}"
            df_log_warn "Backed up .nanorc → .bak_${TIMESTAMP}"
        fi
        [[ -L "${HOME}/.nanorc" ]] && command rm -f "${HOME}/.nanorc"
        cp "${nanorc_src}" "${HOME}/.nanorc"
        df_log_success "Copied ${nanorc_src} → ~/.nanorc"
    else
        df_log_warn ".nanorc missing in ${home_dir}/"
    fi

    # home/config/ → ~/.config/ (with dotglob)
    if [[ -d "${cfg_src_dir}" ]]; then
        df_log_info "Deploying configs from ${cfg_src_dir}"
        mkdir -p "${HOME}/.config"
        shopt -s dotglob nullglob
        if cp -rf "${cfg_src_dir}/." "${HOME}/.config/"; then
            local copied_count
            copied_count=$(find "${cfg_src_dir}" | wc -l)
            df_log_success "Copied ${copied_count} items: home/config/ → ~/.config/"
        else
            df_log_error "Copy failed: ${cfg_src_dir} → ~/.config/"
        fi
        shopt -u dotglob nullglob
    else
        df_log_warn "No home/config/ found"
    fi
}

remove_links() {
    local remove_backups=false
    local src_dir="${DOTFILES_DIR}/home"
    local count=0
    local backup_count=0

    [[ "${1:-}" == "--backup" ]] && remove_backups=true

    df_log_warn "Removing symlinks from ${HOME}..."
    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"
        [[ -d "${src}" ]] && continue

        local dest="${HOME}/${filename}"
        if [[ -L "${dest}" ]]; then
            if command rm -f "${dest}"; then
                df_log_info "Removed: ${filename}"
                ((count++)) || true
            fi
        fi

        if [[ "${remove_backups}" == true ]]; then
            local backup
            for backup in "${HOME}/${filename}".bak_*; do
                if [[ -e "${backup}" ]]; then
                    command rm -f "${backup}" && df_log_info "Removed backup: $(basename "${backup}")"
                    ((backup_count++)) || true
                fi
            done
        fi
    done
    shopt -u dotglob nullglob || true

    df_log_success "Removed ${count} symlinks"
    [[ ${backup_count} -gt 0 ]] && df_log_success "Removed ${backup_count} backups"
    return 0
}

check_status() {
    local src_dir="${DOTFILES_DIR}/home"
    local ok=0
    local err=0

    df_log_info "Status Check: ${src_dir} → ${HOME}"
    shopt -s dotglob nullglob

    local src
    for src in "${src_dir}"/*; do
        local filename
        filename="$(basename "${src}")"
        [[ -d "${src}" ]] && continue

        local dest="${HOME}/${filename}"

        if [[ "${filename}" == ".nanorc" ]]; then
            if [[ -f "${dest}" && ! -L "${dest}" ]]; then
                df_log_success "${filename} (copy OK)"
                ((ok++)) || true
            else
                df_log_error "${filename}: MISSING/WRONG (expect FILE)"
                ((err++)) || true
            fi
            continue
        fi

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

install_single_user() {
    local target_user="${1:?User required}"
    local target_home
    local orig_home

    # Resolve the real home directory for the target user (LDAP/AD/local compatible)
    target_home="$(get_user_home "${target_user}")" || return 1

    df_log_info "Target: ${target_user} → ${target_home}"

    # Preserve caller HOME (important when running via sudo)
    orig_home="${HOME}"

    # Export HOME so all called functions reliably use the target user's home
    export HOME="${target_home}"

    # Backup is optional: do not abort installation if backup fails
    set +e
    backup_dotfiles
    set -e

    # Deploy dotfiles/configs for this HOME
    deploy_dotfiles
    deploy_extra_configs

    # If we are root, fix ownership so the user can actually use the files
    if [[ ${EUID} -eq 0 ]]; then
        local target_group
        target_group="$(id -gn "${target_user}" 2>/dev/null || true)"

        if [[ -n "${target_group}" ]]; then
            [[ -e "${HOME}/.nanorc" ]] && chown "${target_user}:${target_group}" "${HOME}/.nanorc" 2>/dev/null || true
            [[ -d "${HOME}/.config" ]] && chown -R "${target_user}:${target_group}" "${HOME}/.config" 2>/dev/null || true

            # Best-effort: ensure top-level dotfiles in HOME are owned by the user
            find "${HOME}" -maxdepth 1 -name ".*" ! -name "." ! -name ".." -exec chown -h "${target_user}:${target_group}" {} + 2>/dev/null || true
        fi
    fi

    # Restore original HOME for the caller
    export HOME="${orig_home}"

    df_log_success "Done: ${target_user}"
}

# --- MAIN EXECUTION -----------------------------------------------------------

case "${1:-help}" in
    backup)
        backup_dotfiles
        ;;

    install)
        if [[ "${2:-}" == "--all" ]]; then
            df_log_info "Starting multi-user installation..."
            mapfile -t users < <(list_real_users)
            for user in "${users[@]}"; do
                install_single_user "${user}"
            done
        else
            df_log_info "Starting installation for ${USER}..."
            install_single_user "${USER}"
        fi
        ;;

    reinstall)
        df_log_warn "Reinstalling..."
        remove_links
        deploy_dotfiles
        deploy_extra_configs
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
        show_usage
        exit 1
        ;;
esac
