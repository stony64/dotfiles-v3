#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.4.3
# DESCRIPTION:  Dynamisches Deployment & Status-Check für alle Repo-Files.
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. KONFIGURATION ---------------------------------------------------------
readonly REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly DOTFILES_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

log() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

# --- 2. KERNFUNKTIONEN --------------------------------------------------------

deploy() {
    log "DEPLOY: Verlinke alle Dateien aus $DOTFILES_DIR/home -> $HOME"

    # Sicherstellen, dass versteckte Dateien mit einbezogen werden
    shopt -s dotglob nullglob

    for src in "$DOTFILES_DIR/home"/*; do
        # Nur Dateien verarbeiten, Verzeichnisse überspringen (außer 'config')
        [[ -d "$src" ]] && continue

        local filename=$(basename "$src")
        local dest="$HOME/$filename"

        # Falls Ziel eine echte Datei ist -> Backup
        if [[ -f "$dest" && ! -L "$dest" ]]; then
            log "\e[33mWARN\e[0m: $filename ist eine Datei. Backup erstellt."
            mv "$dest" "${dest}.bak_${TIMESTAMP}"
        fi

        ln -snf "$src" "$dest"
        log "\e[32mLINK\e[0m: $filename verknüpft."
    done
    shopt -u dotglob nullglob
}

check_status() {
    log "STATUS: Integritätsprüfung (Basis: Repository-Inhalt)"
    shopt -s dotglob nullglob
    for src in "$DOTFILES_DIR/home"/*; do
        [[ -d "$src" ]] && continue
        local f=$(basename "$src")
        local target="$HOME/$f"

        if [[ -L "$target" ]]; then
            local current_link=$(readlink "$target")
            if [[ "$current_link" == "$src" ]]; then
                echo -e "\e[32m[OK]\e[0m $f"
            else
                echo -e "\e[31m[WRONG]\e[0m $f zeigt auf falsches Ziel!"
            fi
        elif [[ -e "$target" ]]; then
            echo -e "\e[31m[FILE]\e[0m $f ist eine physische Datei (blockiert Link)."
        else
            echo -e "\e[33m[MISSING]\e[0m $f ist nicht im Home verlinkt."
        fi
    done
    shopt -u dotglob nullglob
}

# --- 3. MAIN ------------------------------------------------------------------
case "${1:-help}" in
    install|deploy) deploy ;;
    status)         check_status ;;
    *) echo "Nutzung: $0 {install|status}"; exit 0 ;;
esac
