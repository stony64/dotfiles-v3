#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        core.sh
# VERSION:     3.6.7
# DESCRIPTION: Central Framework Library
# AUTHOR:      Stony64
# CHANGES:     v3.6.7 - Added tar check, improved module loading logs
# ------------------------------------------------------------------------------

# --- GUARD (PREVENT MULTIPLE LOADING) ----------------------------------------
[[ -n "${DF_CORE_LOADED:-}" ]] && return 0
readonly DF_CORE_LOADED=1

# --- FRAMEWORK METADATA -------------------------------------------------------
# SINGLE SOURCE OF TRUTH: All components use this version.
# When releasing: Update only this line!
# - GitHub Actions: parsed via awk (release.yml)
# - Shell-Komponenten: sourced via core.sh
# - Validation: scripts/check-version-consistency.sh
export DF_PROJECT_VERSION="3.6.7"
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- UI CONSTANTS -------------------------------------------------------------
# Use printf for portable ANSI color definitions (not echo)
DF_C_RED=$(printf '\033[31m')
DF_C_GREEN=$(printf '\033[32m')
DF_C_YELLOW=$(printf '\033[33m')
DF_C_BLUE=$(printf '\033[34m')
DF_C_RESET=$(printf '\033[0m')

DF_SYM_OK='[OK]'
DF_SYM_ERR='[ERR]'
DF_SYM_WARN='[! ]'

# --- 1. LOGGING & UI ----------------------------------------------------------

# ------------------------------------------------------------------------------
# df_log_info
#
# Prints informational message in blue.
#
# Parameters: $* - Message text
# Returns: None
# ------------------------------------------------------------------------------
df_log_info() {
    printf '%s--> %s%s\n' "$DF_C_BLUE" "$*" "$DF_C_RESET"
}

# ------------------------------------------------------------------------------
# df_log_success
#
# Prints success message in green with [OK] symbol.
#
# Parameters: $* - Message text
# Returns: None
# ------------------------------------------------------------------------------
df_log_success() {
    printf '%s%s%s %s\n' "$DF_C_GREEN" "$DF_SYM_OK" "$DF_C_RESET" "$*"
}

# ------------------------------------------------------------------------------
# df_log_warn
#
# Prints warning message in yellow with [!] symbol.
#
# Parameters: $* - Message text
# Returns: None
# ------------------------------------------------------------------------------
df_log_warn() {
    printf '%s%s%s %s\n' "$DF_C_YELLOW" "$DF_SYM_WARN" "$DF_C_RESET" "$*"
}

# ------------------------------------------------------------------------------
# df_log_error
#
# Prints error message in red with [ERR] symbol to stderr.
#
# Parameters: $* - Message text
# Returns: None
# ------------------------------------------------------------------------------
df_log_error() {
    printf '%s%s%s %s\n' "$DF_C_RED" "$DF_SYM_ERR" "$DF_C_RESET" "$*" >&2
}

# --- 2. VALIDATION & SYSTEM ---------------------------------------------------

# ------------------------------------------------------------------------------
# is_root_privileged
#
# Checks if current user has root privileges (EUID=0).
# Warns if not root but does not fail hard.
#
# Parameters: None
# Returns: 0 if root, 1 otherwise
# ------------------------------------------------------------------------------
is_root_privileged() {
    local euid
    euid=$EUID

    if (( euid != 0 )); then
        df_log_warn "Root privileges recommended: sudo $(basename "${BASH_SOURCE[1]:-${0}}")"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# is_real_user
#
# Checks if specified user is a real (non-system) user.
# Real users have UID 0 (root) or UID >= 1000.
#
# Parameters: $1 - Username
# Returns: 0 if real user, 1 otherwise
# ------------------------------------------------------------------------------
is_real_user() {
    local target_user_name="${1:?User parameter required}"
    local user_uid

    user_uid=$(getent passwd "$target_user_name" | cut -d: -f3)
    [[ -z "$user_uid" ]] && return 1

    (( user_uid == 0 || user_uid >= 1000 ))
}

# ------------------------------------------------------------------------------
# list_real_users
#
# Lists all real users on the system (UID 0 or >= 1000).
# Excludes system users and nologin shells.
#
# Parameters: None
# Returns: Newline-separated sorted list of real users
# ------------------------------------------------------------------------------
list_real_users() {
    local user_list
    user_list=$(getent passwd | awk -F: '($3==0 || $3>=1000) && $7!~/nologin|false/ {print $1}' | sort -u)
    printf '%s\n' "$user_list"
}

# ------------------------------------------------------------------------------
# get_user_home
#
# Gets home directory for specified user.
# Primary check via getent (LDAP/AD/local compatible).
# Fallback to standard path (/root or /home/<user>).
#
# Parameters: $1 - Username
# Returns: Home path on success, 1 + error on failure
# ------------------------------------------------------------------------------
get_user_home() {
    local target_user_name="${1:?User parameter required}"
    local home_dir

    # Primary check via getent (handles LDAP/AD/local)
    home_dir=$(getent passwd "$target_user_name" | cut -d: -f6)

    if [[ -n "$home_dir" && -d "$home_dir" ]]; then
        printf '%s\n' "$home_dir"
        return 0
    fi

    # Fallback to standard path (useful for fresh Proxmox installs)
    if [[ "$target_user_name" == "root" ]]; then
        home_dir="/root"
    else
        home_dir="/home/$target_user_name"
    fi

    if [[ -d "$home_dir" ]]; then
        printf '%s\n' "$home_dir"
        return 0
    fi

    df_log_error "Home directory not found for: $target_user_name"
    return 1
}

# --- 3. FILE OPERATIONS & BACKUP ----------------------------------------------

# ------------------------------------------------------------------------------
# create_backup
#
# Creates timestamped backup of relevant dotfiles for specified user.
# Creates backup directory, copies files, creates tar.gz archive.
# Checks for tar availability before attempting backup.
#
# Parameters: $1 - Username
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
create_backup() {
    local user_name="${1:?User parameter required}"
    local home_dir timestamp backup_dir backup_file existing_files

    # Check if tar is available
    if ! command -v tar >/dev/null 2>&1; then
        df_log_error "tar not found - backup skipped (install: apt install tar)"
        return 1
    fi

    home_dir=$(get_user_home "$user_name") || return 1
    timestamp=$(date +%Y%m%d_%H%M%S)

    # Create backup directory
    backup_dir="${DF_REPO_ROOT:?}/backup/${user_name}_${timestamp}"
    mkdir -p "$backup_dir" || {
        df_log_error "Failed to create backup directory: $backup_dir"
        return 1
    }

    # Get list of existing files
    existing_files=()
    local files=(.bashrc .profile .bash_profile .vimrc .gitconfig .tmux.conf .ssh/config .bashaliases .bashenv .bashprompt .bashfunctions .bashwartung .dircolors .nanorc)

    for file in "${files[@]}"; do
        [[ -f "${home_dir}/$file" ]] && existing_files+=("$file")
    done

    if [[ ${#existing_files[@]} -gt 0 ]]; then
        df_log_info "Creating backup for $user_name (${#existing_files[@]} files)..."

        backup_file="${backup_dir}/${user_name}_dotfiles.tar.gz"
        if tar -czf "$backup_file" -C "$home_dir" "${existing_files[@]}" 2>/dev/null; then
            local backup_size
            backup_size=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
            df_log_success "Backup created: ${backup_file} (${backup_size})"
            return 0
        else
            df_log_error "Failed to create tar archive"
            return 1
        fi
    else
        df_log_warn "No relevant dotfiles found for $user_name - backup skipped"
        return 0
    fi
}

# ------------------------------------------------------------------------------
# set_owner
#
# Sets owner of path to target user:group.
# Uses id -gn to get group name for user.
#
# Parameters: $1 - Path, $2 - User
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
set_owner() {
    local target_path="${1:?Target path required}"
    local target_user="${2:?Target user required}"
    local target_group_id

    if [[ ! -e "$target_path" ]]; then
        df_log_error "Path does not exist: $target_path"
        return 1
    fi

    target_group_id=$(id -gn "$target_user" 2>/dev/null) || {
        df_log_error "User not found: $target_user"
        return 1
    }

    if chown -R "$target_user:$target_group_id" "$target_path" 2>/dev/null; then
        df_log_success "Owner set: $target_user:$target_group_id → $(basename "$target_path")"
        return 0
    else
        df_log_error "Failed to set owner for: $target_path"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# create_link
#
# Creates symlink with safety checks.
# Backs up existing file, removes broken links.
# Idempotent: Can be run multiple times safely.
#
# Parameters: $1 - Source, $2 - Destination
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
create_link() {
    local source_file="${1:?Source required}"
    local destination_file="${2:?Destination required}"
    local backup_suffix
    backup_suffix=".bak_$(date +%Y%m%d_%H%M%S)"

    [[ ! -e "$source_file" ]] && {
        df_log_error "Source does not exist: $source_file"
        return 1
    }

    # Backup if exists and not link
    if [[ -e "$destination_file" && ! -L "$destination_file" ]]; then
        mv "$destination_file" "${destination_file}${backup_suffix}"
        df_log_warn "Backup: $(basename "$destination_file")${backup_suffix}"
    elif [[ -L "$destination_file" ]]; then
        # Remove if symlink points to different source
        if [[ "$(readlink "$destination_file")" != "$source_file" ]]; then
            rm "$destination_file"
        else
            # Already correct symlink - skip
            return 0
        fi
    fi

    if ln -snf "$source_file" "$destination_file" 2>/dev/null; then
        df_log_success "Link created: $(basename "$destination_file")"
        return 0
    else
        df_log_error "Failed to create link: $(basename "$destination_file")"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# load_modules
#
# Loads all .sh modules from lib/ directory alphabetically.
# Skips core.sh itself to prevent recursion.
# Logs each module load attempt with success/failure status.
#
# Parameters: None
# Returns: 0 success, 1 if any module fails to load
# ------------------------------------------------------------------------------
load_modules() {
    local module_dir="${DF_REPO_ROOT:?}/lib"

    # Skip if lib directory doesn't exist
    [[ ! -d "$module_dir" ]] && {
        df_log_info "No lib/ directory found - module loading skipped"
        return 0
    }

    local module
    local module_count=0
    local loaded_count=0
    local failed_modules=()

    df_log_info "Loading framework modules from lib/..."

    # shellcheck disable=SC2231
    for module in "$module_dir"/*.sh; do
        # Skip if no .sh files exist
        [[ ! -f "$module" ]] && continue

        # Skip core.sh itself
        [[ "$(basename "$module")" == "core.sh" ]] && continue

        (( module_count++ ))

        if source "$module" 2>/dev/null; then
            df_log_success "Loaded: $(basename "$module")"
            (( loaded_count++ ))
        else
            df_log_error "Failed: $(basename "$module")"
            failed_modules+=("$(basename "$module")")
        fi
    done

    # Summary
    if [[ $module_count -eq 0 ]]; then
        df_log_info "No modules found in lib/"
        return 0
    elif [[ ${#failed_modules[@]} -eq 0 ]]; then
        df_log_success "All modules loaded successfully ($loaded_count/$module_count)"
        return 0
    else
        df_log_error "Module loading incomplete: $loaded_count/$module_count succeeded"
        df_log_error "Failed modules: ${failed_modules[*]}"
        return 1
    fi
}
