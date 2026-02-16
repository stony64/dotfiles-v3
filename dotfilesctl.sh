#!/usr/bin/env bash
# --------------------------------------------------------------------------
# FILE:        dotfilesctl.sh
# VERSION:     3.6.9
# DESCRIPTION: Dotfiles Framework Controller
# AUTHOR:      Stony64
# LAST UPDATE: 2026-02-16
# CHANGES:     3.6.9 - Fix reinstall execution flow
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
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="${HOME}/.dotfiles_backups"

# --- HELPER FUNCTIONS ---------------------------------------------------------

show_version() {
    printf 'Dotfiles Framework v%s\n' "${DF_PROJECT_VERSION}"
}

show_usage() {
    cat <<EOF
Dotfiles Framework Controller v${DF_PROJECT_VERSION}

Commands:
  install      Deploy dotfiles via symlinks
  reinstall    Remove + redeploy
  status       Check symlink integrity
  clean        Remove all symlinks
  version      Show version

Examples:
  $(basename "$0") reinstall
  $(basename "$0") status
EOF
}

# --- CORE FUNCTIONS -----------------------------------------------------------

deploy_dotfiles() {
    local src_dir="${DOTFILES_DIR}/home"
    local count=0

    df_log_info "Deploying from ${src_dir}..."

    if [[ ! -d "${src_dir}" ]]; then
        df_log_error "Directory not found: ${src_dir}"
        return 1
    fi

    shopt -s dotglob nullglob

    for src in "${src_dir}"/*; do
        # Skip directories
        if [[ -d "${src}" ]]; then
            continue
        fi

        # Skip backups
        if [[ "$(basename "${src}")" == *.bak* ]]; then
            continue
        fi

        local dest="${HOME}/$(basename "${src}")"

        # Remove old symlink
        if [[ -L "${dest}" ]]; then
            command rm -f "${dest}" || true
        fi

        # Create new symlink
        if ln -sf "${src}" "${dest}"; then
            df_log_success "Linked: $(basename "${src}")"
            ((count++)) || true
        else
            df_log_error "Failed: $(basename "${src}")"
        fi
    done

    shopt -u dotglob nullglob

    printf '\n'
    df_log_success "Deployed ${count} files"
    return 0
}

remove_links() {
    local src_dir="${DOTFILES_DIR}/home"
    local count=0

    df_log_warn "Removing symlinks..."

    shopt -s dotglob nullglob

    for src in "${src_dir}"/*; do
        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/$(basename "${src}")"

        if [[ -L "${dest}" ]]; then
            if command rm -f "${dest}"; then
                df_log_info "Removed: $(basename "${src}")"
                ((count++)) || true
            fi
        fi
    done

    shopt -u dotglob nullglob

    printf '\n'
    df_log_success "Removed ${count} symlinks"
    return 0
}

check_status() {
    local src_dir="${DOTFILES_DIR}/home"
    local ok=0
    local err=0

    df_log_info "Status Check: ${src_dir} → ${HOME}"
    printf '\n'

    shopt -s dotglob nullglob

    for src in "${src_dir}"/*; do
        if [[ -d "${src}" ]]; then
            continue
        fi

        local dest="${HOME}/$(basename "${src}")"

        if [[ -L "${dest}" ]]; then
            local target
            target=$(readlink "${dest}")
            if [[ "${target}" == "${src}" ]]; then
                df_log_success "$(basename "${src}")"
                ((ok++)) || true
            else
                df_log_error "WRONG: $(basename "${src}")"
                ((err++)) || true
            fi
        else
            df_log_error "MISSING: $(basename "${src}")"
            ((err++)) || true
        fi
    done

    shopt -u dotglob nullglob

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
    install)
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
        remove_links
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
