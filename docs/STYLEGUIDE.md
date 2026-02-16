# Dotfiles Framework Style-Guide (v1.5.0) ##

## 1. Dateistruktur & Header ##

**Jede** Framework-Datei folgt **exakt** diesem Template (whitespace-sensitiv):

````bash
#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# FILE:        <Pfad/Name relativ zu Repo-Root> (z.B. home/.bashrc)
# VERSION:     <X.Y.Z> (3 Komponenten, sync mit core.sh)
# DESCRIPTION: <1-Satz Zweck auf Deutsch>
# AUTHOR:      Stony64
# ------------------------------------------------------------------------------

set -euo pipefail  # Exit on error, undefined vars, pipe failures
````

### Idempotency Guard (Sourced Files **PFlicht**) ###

````bash
[[ "${DF_CORE_LOADED:-0}" -eq 1 ]] && return 0
readonly DF_CORE_LOADED=1
````

## 2. Dokumentation & Modul-Gliederung ##

### Funktions-Header (Jede Funktion) ###

````bash
# ------------------------------------------------------------------------------
# backup_dotfiles
# Creates timestamped backup → tar.gz in ~/.dotfiles_backups/
# Returns: 0 success, 1 failure
# ------------------------------------------------------------------------------
backup_dotfiles() {
    local backup_root="${BACKUP_DIR:?}"
    # ...
}
````

### Logische Sektionen (Block-Headers) ###

````bash
# --- 1. CONFIGURATION ---------------------------------------------------------
# --- 2. CORE FUNCTIONS --------------------------------------------------------
# --- 3. MAIN EXECUTION --------------------------------------------------------
````

## 3. Namenskonventionen ##

| Typ                | Präfix   | Beispiele                  | Verwendung                   |
| ------------------ | -------- | -------------------------- | ---------------------------- |
| **Framework-Core** | `df_`    | `df_log_info`, `df_deploy` | **Exklusiv** Framework-Logik |
| **User-Tools**     | Kein     | `backup`, `deploy`, `dctl` | Terminal-freundlich          |
| **Globals**        | `DF_`    | `DF_PROJECT_VERSION`       | Exportiert                   |
| **Lokals**         | `lower_` | `local timestamp`          | `local` am Funktions-Start   |

## 4. Logging (Framework-Pflicht) ##

**Exklusiv** `df_log_*` verwenden:

````bash
df_log_info "Deploying from $src_dir..."
df_log_success "Backup: backup-$timestamp.tar.gz"
df_log_error "Source directory missing!" >&2
df_log_warn "File exists → backup created"
````

## 5. Bash Shebang & Strict Mode (P0) ##

**Jede** Datei:

````bash
#!/usr/bin/env bash
set -euo pipefail  # FAIL-FAST Standard
````

## 6. Security & Robustheit ##

| Regel          | Code                    | Zweck                   |
| -------------- | ----------------------- | ----------------------- |
| **Quoting**    | `"$var"`                | Immer!                  |
| **Null-Guard** | `${VAR:?}`              | Fail-fast required vars |
| **Arrays**     | `"${arr[@]}"`           | Safe expansion          |
| **Word-Split** | `for f in "${arr[@]}";` | Kein `*`!               |

**Root-Safety:**

````bash
[[ $EUID -eq 0 ]] && { df_log_error "Root not permitted"; exit 1; }
````

## 7. GitHub Actions Integration ##

**Versions sync:** `core.sh` → GitHub parses:

````bash
export DF_PROJECT_VERSION="3.6.5"
````

**Release-Trigger:** `git tag v3.6.5 && git push --tags`

## 8. Statische Analyse (0 Warnings) ##

| Tool             | Status     | Config                    |
| ---------------- | ---------- | ------------------------- |
| **ShellCheck**   | 0 Warnings | `.shellcheckrc`           |
| **markdownlint** | SARIF      | `markdownlint-cli2.jsonc` |
| **EditorConfig** | enforced   | `.editorconfig`           |

**Disable nur begründet:**

````bash
# shellcheck disable=SC1073  # MC INI intentional
````

## 9. VSCode & Editor-Setup ##

````jsonc
"[shellscript]": {
    "editor.defaultFormatter": "foxundermoon.shell-format",
    "editor.formatOnSave": true
}
````

## 10. Datei-Deploy (dctl) ##

| Aktion                  | Backup             | Symlink    |
| ----------------------- | ------------------ | ---------- |
| **Bestehende Datei**    | `.bak_<timestamp>` | ✅ Ersetzt |
| **Bestehender Symlink** | Kein Backup        | ✅ Ersetzt |
| **Fehlt**               | -                  | ✅ Neu     |

---
