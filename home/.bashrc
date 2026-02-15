#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:          .bashrc
# VERSION:       1.7.1
# DESCRIPTION:   Hauptkonfigurationsdatei mit deterministischem Modul-Loader.
# AUTHOR:        Stony64
# ------------------------------------------------------------------------------

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

: "${DF_PROJECT_VERSION:=3.6.3}"

# --- 4. DETERMINISTISCHER MODUL-LOADER ----------------------------------------
# Wir laden Module in einer festen Reihenfolge, um Abhängigkeiten zu wahren.
# 1. ENV -> 2. FUNCTIONS -> 3. ALIASES -> 4. PROMPT -> 5. REST
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
        # Vermeide doppeltes Laden durch den Wildcard-Loop später
        # shellcheck source=/dev/null
        source "$mod_path"
        # Markiere als geladen für den optionalen Dynamic-Loop
        eval "LOADED_${mod_name//./_}=1"
    fi
done

# --- 5. FRAMEWORK + SYSTEM ALIASE ---------------------------------------------

reload() {
    # Wir sourcen die .bashrc neu
    if source "${HOME}/.bashrc"; then
        if command -v df_log_success >/dev/null 2>&1; then
            df_log_success "Shell v${DF_PROJECT_VERSION} neu geladen."
        else
            printf '\033[32m[OK]\033[0m Shell neu geladen.\n'
        fi
    fi
}

# dctl Alias (Sicherheits-Fallback)
if ! command -v dctl >/dev/null 2>&1; then
    alias dctl='sudo /opt/dotfiles/dotfilesctl.sh'
fi

tools() {
    local b="${DF_C_BLUE:-}"
    local r="${DF_C_RESET:-}"

    # SC2059 Fix: Variablen nicht im Format-String
    printf "\n%bFramework Tools v%s:%b\n" "$b" "${DF_PROJECT_VERSION}" "$r"
    printf "  reload     → Shell-Konfiguration frisch einlesen\n"
    printf "  dctl       → Dotfiles Management Utility\n"
    printf "  dutop      → Top 10 Platzfresser (aktuell)\n"
    printf "  dutopall   → Top 10 Platzfresser (rekursiv)\n"
    printf "  path       → Formatierten \$PATH anzeigen\n"
    printf "  myip       → Lokale & Öffentliche IP prüfen\n\n"

    if command -v dctl >/dev/null 2>&1; then
        dctl status
    fi
}

# --- 6. ABSCHLUSS -------------------------------------------------------------
# Begrüßung erst ganz am Ende, wenn alle Funktionen geladen sind
if command -v df_log_info >/dev/null 2>&1; then
    df_log_info "Framework v${DF_PROJECT_VERSION} aktiv. Tippe 'tools' für Hilfe."
fi
