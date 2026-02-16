#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        home/.bashrc
# VERSION:     3.6.7
# DESCRIPTION: Main Configuration with Deterministic Module Loading
# AUTHOR:      Stony64
# CHANGES:     v3.6.7 - Add stty -ixon for editor shortcuts
# ------------------------------------------------------------------------------

# ShellCheck configuration
# shellcheck source=/dev/null disable=SC2034

# --- INTERACTIVE CHECK --------------------------------------------------------
# Exit immediately if not running interactively
[[ $- != *i* ]] && return

# --- PROJECT ENVIRONMENT ------------------------------------------------------
export DF_REPO_ROOT="${DF_REPO_ROOT:-/opt/dotfiles}"
export DF_CORE="${DF_REPO_ROOT}/core.sh"

# --- CORE LIBRARY LOADING -----------------------------------------------------
if [[ -f "$DF_CORE" ]]; then
    # shellcheck source=/dev/null
    source "$DF_CORE"

    if [[ -z "${DF_PROJECT_VERSION:-}" ]]; then
        printf '\033[33m[WARN]\033[0m DF_PROJECT_VERSION not set by core.sh\n' >&2
    fi
else
    printf '\033[31m[ERR]\033[0m Core library not found: %s\n' "$DF_CORE" >&2
    printf '\033[33m[INFO]\033[0m Continuing with limited functionality...\n' >&2

    # Fallback: Define minimal logging functions
    if ! command -v df_log_info >/dev/null 2>&1; then
        df_log_info()  { printf '\033[34m-->\033[0m %s\n' "$*"; }
        df_log_error() { printf '\033[31m[ERR]\033[0m %s\n' "$*" >&2; }
        df_log_warn()  { printf '\033[33m[WARN]\033[0m %s\n' "$*" >&2; }
    fi

    # Set fallback version
    export DF_PROJECT_VERSION="${DF_PROJECT_VERSION:-3.6.7-fallback}"
fi

# ==============================================================================
# TERMINAL: Disable XON/XOFF Flow Control
# ==============================================================================
# Enables Ctrl+S and Ctrl+Q as normal shortcuts in editors (nano, vim, less)
#
# Background:
#   XON/XOFF flow control is a legacy feature from serial terminal days.
#   Ctrl+S (XOFF) paused terminal output, Ctrl+Q (XON) resumed it.
#   This is rarely needed on modern systems and conflicts with editor shortcuts.
#
# Impact:
#   - Ctrl+S in nano: Save file (Write Out)
#   - Ctrl+Q in nano: Quit editor
#   - Ctrl+S in vim:  Can be mapped to save
#   - Ctrl+S in less: Forward search
#
# Disable with: stty ixon (to re-enable flow control if needed)
# ==============================================================================
stty -ixon 2>/dev/null

# --- DETERMINISTIC MODULE LOADER ----------------------------------------------
# Load modules in fixed order to respect dependencies:
#   1. ENV         → Environment variables and shell options
#   2. FUNCTIONS   → Bash functions (archive, search, network)
#   3. ALIASES     → Command aliases and shortcuts
#   4. PROMPT      → PS1 configuration with Git awareness
#   5. MAINTENANCE → System maintenance helpers

declare -a df_modules=(
    ".bashenv"
    ".bashfunctions"
    ".bashaliases"
    ".bashprompt"
    ".bashwartung"
)

for mod_name in "${df_modules[@]}"; do
    mod_path="${HOME}/${mod_name}"

    if [[ -r "$mod_path" ]]; then
        # shellcheck source=/dev/null
        source "$mod_path" || {
            printf '\033[33m[WARN]\033[0m Failed to load: %s\n' "$mod_name" >&2
        }
    else
        # Silent skip for optional modules (e.g., .bashwartung on non-Proxmox)
        :
    fi
done

# --- FRAMEWORK UTILITIES ------------------------------------------------------

# ------------------------------------------------------------------------------
# reload_shell
#
# Reloads shell configuration by re-sourcing .bashrc.
# Useful when configuration changes are made and reload is desired.
#
# Parameters: None
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
reload_shell() {
    local bashrc_path="${HOME}/.bashrc"

    if [[ ! -r "$bashrc_path" ]]; then
        printf '\033[31m[ERR]\033[0m .bashrc not found or not readable\n' >&2
        return 1
    fi

    # Re-source the configuration
    # shellcheck source=/dev/null
    if source "$bashrc_path"; then
        printf '\033[32m[OK]\033[0m Shell configuration reloaded\n'
        return 0
    else
        printf '\033[31m[ERR]\033[0m Failed to reload shell configuration\n' >&2
        return 1
    fi
}

# Alias for convenience
alias reload='reload_shell'

# ------------------------------------------------------------------------------
# dctl (Dotfiles Controller Alias)
#
# Security fallback: Only create alias if dctl is not already in PATH.
# Prevents accidental override of installed dctl binary.
# ------------------------------------------------------------------------------
if ! command -v dctl >/dev/null 2>&1; then
    alias dctl='sudo "${DF_REPO_ROOT}/dotfilesctl.sh"'
fi

# ------------------------------------------------------------------------------
# tools
#
# Displays all available tools within the dotfiles framework.
# Shows framework version and quick reference for common commands.
#
# Parameters: None
# Returns: None
# ------------------------------------------------------------------------------
tools() {
    local version="${DF_PROJECT_VERSION:-unknown}"
    local color_blue="${DF_C_BLUE:-\033[34m}"
    local color_reset="${DF_C_RESET:-\033[0m}"

    printf '\n%s=== Dotfiles Framework v%s ===%s\n\n' "$color_blue" "$version" "$color_reset"

    cat <<'EOF'
Core Commands:
  reload       → Reload shell configuration
  dctl         → Dotfiles management utility
  tools        → Show this help

Utilities:
  myip         → Show local and public IP addresses
  path         → Display formatted $PATH
  hg <term>    → Search command history
  ff <name>    → Find files by name
  ft <text>    → Find text in files
  mkcd <dir>   → Create directory and cd into it
  extract <f>  → Universal archive extractor

System (requires root):
  au           → Quick APT update
  au-full      → Full system maintenance (APT + ZFS + Locate)

Git Shortcuts:
  st           → git status
  co           → git checkout
  br           → git branch -v
  cm <msg>     → git commit -m "msg"
  lg           → Pretty git log (last 15 commits)

EOF

    # Show dotfiles status if dctl is available
    if command -v dctl >/dev/null 2>&1; then
        printf '%sStatus Check:%s\n' "$color_blue" "$color_reset"
        dctl status 2>/dev/null || printf '  (Run: sudo dctl status)\n'
    fi

    printf '\n'
}

# --- FINALIZATION -------------------------------------------------------------
# Greeting message after all modules are loaded
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Framework v${DF_PROJECT_VERSION} loaded. Type 'tools' for help."
fi
