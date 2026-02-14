#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:          .bashrc
# VERSION:       1.6.1
# DESCRIPTION:   Hauptkonfigurationsdatei mit dynamischem Modul-Loader.
# AUTHOR:        Stony64
# ------------------------------------------------------------------------------
# shellcheck shell=bash

# --- 1. INTERAKTIV-CHECK ------------------------------------------------------
[[ $- != *i* ]] && return

# --- 2. PROJEKT-UMGEBUNG ------------------------------------------------------
export DF_REPO_ROOT="/opt/dotfiles"
export DF_CORE="${DF_REPO_ROOT}/core.sh"

# --- 3. KERN-BIBLIOTHEK LADEN -------------------------------------------------
if [[ -f "$DF_CORE" ]]; then
    # shellcheck source=/dev/null
    source "$DF_CORE"
else
    printf '\033[31m[ERR]\033[0m Core-Library nicht gefunden: %s\n' "$DF_CORE" >&2
fi

# FIX SC2154: Sicherstellen, dass die Variable existiert (Fallback auf 0.0.0)
# Falls sie in core.sh definiert wurde, bleibt jener Wert erhalten.
: "${DF_PROJECT_VERSION:=0.0.0}"

# --- 4. MODULE DYNAMISCH LADEN ------------------------------------------------
[[ -r "${HOME}/.bashenv" ]] && source "${HOME}/.bashenv"

for module_path in "${HOME}"/.bash[^.]*; do
    # Verhindere das Laden von .bashrc (Loop) oder .bash_history
    [[ "$module_path" == *"/.bashrc"* ]] && continue
    [[ "$module_path" == *"/.bash_history"* ]] && continue
    [[ -r "$module_path" ]] || continue

    filename=$(basename "$module_path")

    # Sicherer Aufruf der Log-Funktion
    if command -v df_log_info >/dev/null 2>&1; then
        df_log_info "Lade Modul: $filename"
    fi

    # shellcheck source=/dev/null
    source "$module_path"
done

# --- 5. FRAMEWORK + SYSTEM ALIASE ---------------------------------------------

# FIX SC2015/SC2139: Umstellung auf eine Funktion für 'reload'
# Das ist sauberer als ein langer Alias-String mit Logik.
reload() {
    if source "${HOME}/.bashrc"; then
        if command -v df_log_success >/dev/null 2>&1; then
            df_log_success "Shell v${DF_PROJECT_VERSION} neu geladen."
        else
            echo "[OK] Shell neu geladen."
        fi
    fi
}

# Dotfiles Control
if ! command -v dctl >/dev/null 2>&1; then
    alias dctl='sudo "${DF_REPO_ROOT}/dotfilesctl.sh"'
fi

# Disk Usage
alias dutop='LC_ALL=C du -hs * 2>/dev/null | LC_ALL=C sort -rh | LC_ALL=C head -n 10'
alias dutopall='LC_ALL=C du -hs ** 2>/dev/null | LC_ALL=C sort -rh | LC_ALL=C head -n 10'

# Framework Tools Übersicht (Als Funktion für bessere Wartbarkeit)
tools() {
    local blue='\033[34m'
    local reset='\033[0m'
    printf "\n%bFramework Tools:%b\n" "${DF_C_BLUE:-$blue}" "${DF_C_RESET:-$reset}"
    printf "  reload   → Shell neu laden\n"
    printf "  dctl     → Dotfiles Framework\n"
    printf "  dutop    → Disk Top 10\n"
    printf "  dutopall → Rekursiv Top 10\n"
    if command -v df_log_info >/dev/null 2>&1; then
        df_log_info "Status: dctl status $USER"
    fi
}

# --- 6. PROMPT CUSTOM ---------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    PS1='\[\033[31m\]\h:\w\$\[\033[0m\] '
else
    PS1='\[\033[32m\]\u@\h:\w\$\[\033[0m\] '
fi

# --- 7. ABSCHLUSS -------------------------------------------------------------
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Dotfiles Framework v${DF_PROJECT_VERSION} → ready! (tools)"
fi
