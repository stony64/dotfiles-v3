#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        lib/df-backup.sh
# VERSION:     3.6.6
# DESCRIPTION: Backup Module for Automated User Configuration Snapshots
# TYPE:        Sourced Module (requires core.sh)
# AUTHOR:      Stony64
# CHANGES:     v3.6.6 - Fixed cleanup logic, robust tar handling
# ------------------------------------------------------------------------------

# ShellCheck configuration
# shellcheck source=/dev/null disable=SC2034

# --- IDEMPOTENCY GUARD --------------------------------------------------------
[[ -n "${DF_BACKUP_LOADED:-}" ]] && return 0
readonly DF_BACKUP_LOADED=1

# --- BOOTSTRAP HINTS ----------------------------------------------------------
# Inform ShellCheck about external vars from core.sh
DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"

# --- CONFIGURATION ------------------------------------------------------------
readonly DF_BACKUP_DIR="${DF_REPO_ROOT}/_backups"
readonly DF_BACKUP_RETENTION=5  # Keep last N backups per user

# --- BACKUP CREATION ----------------------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_create
#
# Creates compressed snapshot of user's relevant dotfiles in repository's
# _backups/ directory. Includes .bashrc, .bash_profile, .profile, and .config/.
#
# Creates tarball at: _backups/<user>/snapshot_YYYYMMDD_HHMMSS.tar.gz
#
# Parameters:
#   $1 - Username to backup
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
df_backup_create() {
    local user_name="${1:?Usage: df_backup_create <username>}"
    local home_directory
    local backup_directory
    local backup_file_name
    local timestamp
    local -a backup_targets
    local -a existing_targets

    # Validate user and get home directory
    if ! home_directory=$(get_user_home "$user_name" 2>/dev/null); then
        df_log_error "Backup failed: Home directory not found for $user_name"
        return 1
    fi

    # Setup backup directory in repository
    backup_directory="${DF_BACKUP_DIR}/${user_name}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file_name="${backup_directory}/snapshot_${timestamp}.tar.gz"

    # Ensure backup directory structure
    if [[ ! -d "$backup_directory" ]]; then
        if ! mkdir -p "$backup_directory"; then
            df_log_error "Failed to create backup directory: $backup_directory"
            return 1
        fi
        # Set owner to root if run as root
        if [[ $EUID -eq 0 ]]; then
            chown root:root "$backup_directory" 2>/dev/null || true
        fi
    fi

    df_log_info "Creating backup for $user_name..."

    # Define backup targets (relative to home directory)
    backup_targets=(
        ".bashrc"
        ".bash_profile"
        ".profile"
        ".bashenv"
        ".bashaliases"
        ".bashfunctions"
        ".bashprompt"
        ".gitconfig"
        ".config"
    )

    # Filter to only existing targets (avoid tar errors)
    existing_targets=()
    local target
    for target in "${backup_targets[@]}"; do
        if [[ -e "${home_directory}/${target}" ]]; then
            existing_targets+=("$target")
        fi
    done

    # Check if we have anything to backup
    if [[ ${#existing_targets[@]} -eq 0 ]]; then
        df_log_warn "No backup targets found for $user_name"
        return 1
    fi

    # Perform backup (P0: Data integrity)
    if tar -czf "$backup_file_name" -C "$home_directory" "${existing_targets[@]}" 2>/dev/null; then
        local backup_size
        backup_size=$(du -h "$backup_file_name" | cut -f1)
        df_log_success "Backup created: $(basename "$backup_file_name") (${backup_size})"

        # Automatic cleanup after successful backup
        df_backup_cleanup "$user_name"

        return 0
    else
        df_log_error "Backup failed for $user_name"
        # Remove partial backup file
        rm -f "$backup_file_name" 2>/dev/null
        return 1
    fi
}

# --- BACKUP CLEANUP -----------------------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_cleanup
#
# Removes old backups for specified user, keeping only the last N snapshots
# (configured via DF_BACKUP_RETENTION, default: 5).
#
# Sorts by filename (which includes timestamp) to determine age.
#
# Parameters:
#   $1 - Username to clean up backups for
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
df_backup_cleanup() {
    local user_name="${1:?Usage: df_backup_cleanup <username>}"
    local backup_directory="${DF_BACKUP_DIR}/${user_name}"
    local -a backup_files
    local file_count
    local delete_count

    # Skip if backup directory doesn't exist
    [[ ! -d "$backup_directory" ]] && return 0

    # Get list of backup files sorted by name (timestamp-based)
    mapfile -t backup_files < <(find "$backup_directory" -name 'snapshot_*.tar.gz' -type f | sort)

    file_count=${#backup_files[@]}

    # Check if cleanup is needed
    if [[ $file_count -le $DF_BACKUP_RETENTION ]]; then
        return 0
    fi

    # Calculate how many to delete
    delete_count=$((file_count - DF_BACKUP_RETENTION))

    df_log_info "Cleaning up old backups for $user_name (keeping last ${DF_BACKUP_RETENTION})..."

    # Delete oldest backups
    local i
    for (( i=0; i<delete_count; i++ )); do
        if rm -f "${backup_files[$i]}" 2>/dev/null; then
            df_log_info "Removed: $(basename "${backup_files[$i]}")"
        else
            df_log_warn "Failed to remove: $(basename "${backup_files[$i]}")"
        fi
    done

    df_log_success "Cleanup complete: removed $delete_count old backup(s)"
    return 0
}

# --- BACKUP RESTORATION (Optional) --------------------------------------------

# ------------------------------------------------------------------------------
# df_backup_list
#
# Lists all available backups for specified user.
#
# Parameters:
#   $1 - Username
# Returns: None (prints to stdout)
# ------------------------------------------------------------------------------
df_backup_list() {
    local user_name="${1:?Usage: df_backup_list <username>}"
    local backup_directory="${DF_BACKUP_DIR}/${user_name}"

    if [[ ! -d "$backup_directory" ]]; then
        df_log_warn "No backups found for $user_name"
        return 1
    fi

    df_log_info "Available backups for $user_name:"

    local -a backup_files
    mapfile -t backup_files < <(find "$backup_directory" -name 'snapshot_*.tar.gz' -type f | sort -r)

    if [[ ${#backup_files[@]} -eq 0 ]]; then
        df_log_warn "No backup files found"
        return 1
    fi

    local file
    local size
    for file in "${backup_files[@]}"; do
        size=$(du -h "$file" | cut -f1)
        printf "  - %s (%s)\n" "$(basename "$file")" "$size"
    done

    return 0
}
