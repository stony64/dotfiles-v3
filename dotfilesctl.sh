#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.4.0
# DESCRIPTION:  CLI-Entrypoint zur Distribution von Konfigurationsdateien.
#               Fix: Shell-Exit bei Hilfe, Symlink-Pfade & Auto-Backup.
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. KONFIGURATION & KONSTANTEN --------------------------------------------
readonly REAL_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly SCRIPT_DIR="$(cd "$(dirname "$REAL_PATH")" && pwd)"
readonly SCRIPT_NAME="$(basename "$REAL_PATH")"
readonly DOTFILES_DIR="$SCRIPT_DIR"


# --- 2. HILFSFUNKTIONEN -------------------------------------------------------
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }

# Bereinigt alte Backups im Home-Verzeichnis (> 30 Tage)
cleanup_backups() {
    log "CLEANUP: Suche nach alten .bak_ Dateien in $HOME..."
    find "$HOME" -maxdepth 1 -name ".*.bak_*" -type f -mtime +30 -exec rm -v {} \;
    log "CLEANUP: Abgeschlossen."
}

# --- 3. KERNFUNKTIONEN --------------------------------------------------------

backup() {
    log "BACKUP: Initialisiere Sicherung in $BACKUP_BASE"
    mkdir -p "$BACKUP_BASE"
    local targets=(
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.gitconfig"
        "$HOME/.tmux.conf" "$HOME/.vimrc"
    )
    for item in "${targets[@]}"; do
        if [[ -e "$item" ]]; then
            local dest="$BACKUP_BASE${item}"
            mkdir -p "$(dirname "$dest")"
            cp -a "$item" "$dest"
            log "BACKUP: $item gesichert."
        fi
    done
    tar czf "$HOME/dotfiles-backup-$TIMESTAMP.tar.gz" -C "$HOME" ".dotfiles-backup-$TIMESTAMP"
    rm -rf "$BACKUP_BASE"
    log "BACKUP: Archiv erstellt: ~/dotfiles-backup-$TIMESTAMP.tar.gz"
}

deploy() {
    log "DEPLOY: Starte Deployment aus $DOTFILES_DIR/home"
    # Pfade wurden auf /home/ korrigiert, da dort deine Dateien liegen
    local user_mappings=(
        "$DOTFILES_DIR/home/.bashrc:$HOME/.bashrc"
        "$DOTFILES_DIR/home/.bash_profile:$HOME/.bash_profile"
        "$DOTFILES_DIR/home/.gitconfig:$HOME/.gitconfig"
        "$DOTFILES_DIR/home/.tmux.conf:$HOME/.tmux.conf"
        "$DOTFILES_DIR/home/.vimrc:$HOME/.vimrc"
    )

    for mapping in "${user_mappings[@]}"; do
        local src dest
        IFS=':' read -r src dest <<< "$mapping"

        if [[ -f "$src" ]]; then
            # FIX für [ERROR]: Wenn Ziel eine echte Datei ist, wegschieben
            if [[ -f "$dest" && ! -L "$dest" ]]; then
                log "WARN: $dest ist eine Datei. Erstelle Sicherheits-Backup..."
                mv "$dest" "${dest}.bak_${TIMESTAMP}"
            fi

            mkdir -p "$(dirname "$dest")"
            # FIX: ln -snf überschreibt auch fehlerhafte Links/Dateien
            ln -snf "$src" "$dest"
            log "LINK: $dest -> $src"
        else
            log "SKIP: Quelle $src nicht gefunden."
        fi
    done
    log "DEPLOY: Erfolgreich abgeschlossen."
}

check_status() {
    log "STATUS: Überprüfe Symlink-Integrität..."
    local files=(".bashrc" ".bash_profile" ".gitconfig" ".tmux.conf" ".vimrc")
    for f in "${files[@]}"; do
        local target="$HOME/$f"
        if [[ -L "$target" ]]; then
            echo "[OK] $f -> $(readlink "$target")"
        elif [[ -e "$target" ]]; then
            echo "[ERROR] $f ist eine reguläre Datei (kein Symlink)."
        else
            echo "[MISSING] $f existiert nicht."
        fi
    done
}

# --- 4. EXECUTION CONTROLLER (MAIN) -------------------------------------------
main() {
    case "${1:-help}" in
        backup)  backup ;;
        install|deploy) deploy ;;
        status)  check_status ;;
        cleanup) cleanup_backups ;;
        *)
            cat <<EOF
Nutzung: $SCRIPT_NAME {backup|install|status|cleanup}

Befehle:
  backup    Sichert aktuelle Configs in ein versioniertes tar.gz.
  install   Setzt Symlinks aus /home ins User-Verzeichnis.
  status    Prüft die Integrität der lokalen Symlinks.
  cleanup   Löscht Backups im Home, die älter als 30 Tage sind.

Version: 3.4.0 (Core: ${DF_PROJECT_VERSION:-v3.3.0})
EOF
            # FIX: exit 0 verhindert das Schließen der SSH-Shell
            exit 0
            ;;
    esac
}

main "$@"
