#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:         dotfilesctl.sh
# VERSION:      3.3.5
# DESCRIPTION:  CLI-Entrypoint zur Distribution von Konfigurationsdateien.
#               Verwaltet Symlinks für User-Home und System-Ebene (/etc).
#               Optimiert für Debian GNU/Linux & Proxmox VE.
# AUTHOR:       Stony64
# ------------------------------------------------------------------------------
# Technischer Hinweis: set -euo pipefail sorgt für sofortigen Abbruch bei Fehlern.
# SC2310 wird vermieden, indem Funktionen nicht in Bedingungen aufgerufen werden.
# ------------------------------------------------------------------------------
set -euo pipefail

# --- 1. KONFIGURATION & KONSTANTEN --------------------------------------------

# Pfad zum Repository-Root (Speicherort dieses Skripts)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly DOTFILES_DIR="$SCRIPT_DIR"

# Zeitstempel für eindeutige Backup-Verzeichnisse
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Temporäres Backup-Verzeichnis vor der Archivierung
readonly BACKUP_BASE="$HOME/.dotfiles-backup-$TIMESTAMP"

# --- 2. HILFSFUNKTIONEN -------------------------------------------------------

# Zentrales Logging für Statusmeldungen (Standardfehler für saubere Pipes)
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Prüft auf Root-Berechtigungen (wichtig für System-Operationen)
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log "REQUIRED: Diese Operation erfordert sudo-Rechte."
        return 1
    fi
}

# Interne Funktion zum Sichern eines Pfades
# Rückgabewert 0 (Erfolg) auch wenn Datei fehlt, um set -e nicht zu triggern.
_internal_backup_perform() {
    local target_path="$1"
    local destination="$BACKUP_BASE${target_path}"

    # Existenzprüfung intern, damit der Aufrufer keine 'if'-Bedingung braucht (SC2310)
    if [[ -e "$target_path" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp -a "$target_path" "$destination"
        log "BACKUP: $target_path gesichert."
    else
        log "INFO: $target_path nicht vorhanden, überspringe..."
    fi
}

# --- 3. KERNFUNKTIONEN --------------------------------------------------------

# Erstellt eine Sicherung der aktuell aktiven Konfigurationen
backup() {
    log "BACKUP: Initialisiere Sicherung in $BACKUP_BASE"
    mkdir -p "$BACKUP_BASE"

    # Liste der kritischen Pfade (User & System)
    local targets=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.gitconfig"
        "$HOME/.tmux.conf"
        "$HOME/.vimrc"
        "$HOME/.config/nvim/init.vim"
        "/etc/systemd/user/pipewire.service.d/99-proxmox.conf"
        "/etc/zfs/zpool.cache"
    )

    # Nackter Aufruf ohne logische Verknüpfung sichert set -e Funktionalität
    for item in "${targets[@]}"; do
        _internal_backup_perform "$item"
    done

    # Finalisierung: Backup-Ordner in ein komprimiertes Archiv packen
    tar czf "$HOME/dotfiles-backup-$TIMESTAMP.tar.gz" -C "$HOME" ".dotfiles-backup-$TIMESTAMP"
    log "BACKUP: Archiv erstellt: ~/dotfiles-backup-$TIMESTAMP.tar.gz"

    # Aufräumen des temporären Verzeichnisses
    rm -rf "$BACKUP_BASE"
}

# Rollt die Symlinks aus dem Repository in das System aus
deploy() {
    log "DEPLOY: Starte Deployment aus $DOTFILES_DIR"

    # Mapping-Array: "QUELLE:ZIEL"
    local user_mappings=(
        "$DOTFILES_DIR/dotfiles/bashrc:$HOME/.bashrc"
        "$DOTFILES_DIR/dotfiles/bash_profile:$HOME/.bash_profile"
        "$DOTFILES_DIR/dotfiles/gitconfig:$HOME/.gitconfig"
        "$DOTFILES_DIR/dotfiles/tmux.conf:$HOME/.tmux.conf"
        "$DOTFILES_DIR/dotfiles/vimrc:$HOME/.vimrc"
    )

    for mapping in "${user_mappings[@]}"; do
        local src dest
        IFS=':' read -r src dest <<< "$mapping"

        if [[ -f "$src" ]]; then
            mkdir -p "$(dirname "$dest")"
            # -f erzwingt das Überschreiben existierender (falscher) Symlinks
            ln -sf "$src" "$dest"
            log "LINK: $dest -> $src"
        else
            log "SKIP: Quelle $src nicht im Repository gefunden."
        fi
    done

    # System-spezifische Konfigurationen (z.B. für Proxmox/ZFS)
    if [[ -d "$DOTFILES_DIR/etc" ]]; then
        log "SYS: Konfiguriere System-Komponenten..."

        sudo mkdir -p "/etc/systemd/user/pipewire.service.d/"
        # Nutze absoluten Pfad für Symlinks im System-Bereich
        sudo ln -sf "$DOTFILES_DIR/etc/proxmox.conf" "/etc/systemd/user/pipewire.service.d/99-proxmox.conf"

        # ZFS Cachefile Optimierung (nur wenn zpool vorhanden)
        if command -v zpool >/dev/null; then
            # Prüfe Pool-Status ohne Exit bei Fehler (SC2310 konform)
            if sudo zpool list proxmox >/dev/null 2>&1; then
                sudo zpool set cachefile=/etc/zfs/zpool.cache proxmox
                log "SYS: ZFS Cachefile für 'proxmox' gesetzt."
            else
                log "WARN: ZFS Pool 'proxmox' nicht aktiv, Cache-Setting übersprungen."
            fi
        fi
    fi

    log "DEPLOY: Erfolgreich abgeschlossen."
}

# Validiert den Zustand der Symlinks im Home-Verzeichnis
check_status() {
    log "STATUS: Überprüfe Symlink-Integrität..."
    local files=(".bashrc" ".bash_profile" ".gitconfig" ".tmux.conf" ".vimrc")

    for f in "${files[@]}"; do
        if [[ -L "$HOME/$f" ]]; then
            # Zeigt das Ziel des Symlinks an
            echo "[OK] $f -> $(readlink "$HOME/$f")"
        elif [[ -e "$HOME/$f" ]]; then
            echo "[ERROR] $f ist eine reguläre Datei (kein Symlink)."
        else
            echo "[MISSING] $f existiert nicht."
        fi
    done
}

# --- 4. EXECUTION CONTROLLER (MAIN) -------------------------------------------

main() {
    # Falls kein Argument übergeben wurde, Hilfe anzeigen
    case "${1:-help}" in
        backup)
            backup
            ;;
        install|deploy)
            deploy
            ;;
        status)
            check_status
            ;;
        *)
            # Here-Doc für die CLI-Nutzungshilfe
            cat <<EOF
Nutzung: $SCRIPT_NAME {backup|install|status}

Befehle:
  backup    Sichert aktuelle Configs in ein versioniertes tar.gz.
  install   Setzt Symlinks und wendet System-Parameter an.
  status    Prüft die Integrität der lokalen Symlinks.

Version: $DF_PROJECT_VERSION (Core: v3.3.0)
EOF
            exit 0
            ;;
    esac
}

# Startet das Skript mit allen übergebenen Parametern
main "$@"
