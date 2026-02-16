# 🛠 Dotfiles Framework v3.6.5 ##

Ein hochgradig modularer, **Multi-User-fähiger** Dotfiles-Manager für **Proxmox/Debian** – zentrale Konfigurations-Verteilung unter `/opt/dotfiles`.

## 🌟 Hauptmerkmale ##

- **Modulare Architektur** – Logik in `lib/` (`df_*`).
- **Sichere Backups** – `.tar.gz` vor Änderungen (Idempotenz P1).
- **Multi-User** – `dctl install $USER` oder `--all`.
- **Proxmox/ZFS** – Panelize-Suchen (mc.ini).
- **ShellCheck-clean** – 0 Warnings, GitHub Actions.

## 📁 Projektstruktur ##

```
core.sh                    # Kern (DF_PROJECT_VERSION)
dotfilesctl.sh             # CLI: dctl install/status
├── lib/                   # df_* Module (backup/deploy/log)
├── home/                  # Dotfiles (.bash*, mc/ini)
│   ├── .bash*             # Shell (bashrc, aliases, functions)
│   └── config/
│       └── mc/            # Midnight Commander
├── docs/                  # Dokumentation
│   └── STYLEGUIDE.md      # Bash/ShellCheck Guide
├── .github/workflows/     # Lint/Release Actions
├── .shellcheckrc          # ShellCheck Config
├── markdownlint-cli2.jsonc # MD-Lint (SARIF)
├── .editorconfig          # 4-Spaces (shfmt)
└── .gitattributes         # LF + exec
```

## 🚀 Installation ##

### 1. Framework installieren ###

```bash
sudo git clone --depth=1 https://github.com/Stony64/dotfiles-v3 /opt/dotfiles
sudo /opt/dotfiles/dotfilesctl.sh install $USER
source ~/.bashrc
```

**`/usr/local/bin/dctl`** wird automatisch verlinkt!

### 2. Tägliche Nutzung ###

```bash
dctl status    # Link-Check
dctl backup    # tar.gz Backup
dctl install   # Update + Backup
dctl reinstall # Hard-Reset
```

**Safety:** Backups vor **jeder** Änderung → **Zero Downtime**.

## 🔍 Proxmox Integration (mc.ini) ##

**F9 → Panelize:**

```
Proxmox VMs     # qm list
Proxmox CTs     # pct list
ZFS Datasets    # zfs list -Ho
Docker Images   # docker images
Shell Scripts   # find *.sh -executable
```

## 🛠 Standards ##

| Tool             | Config                    | Status     |
|------------------|---------------------------|------------|
| **ShellCheck**   | `.shellcheckrc`           | 0 Warnings |
| **markdownlint** | `markdownlint-cli2.jsonc` | SARIF      |
| **EditorConfig** | `.editorconfig`           | 4-Spaces   |

**Strict Mode:** `set -euo pipefail`

## 📦 Quick Assets ##

- [dctl](dotfilesctl.sh) – CLI Binary
- [core.sh](core.sh) – Version/Logging
- [ZIP](https://github.com/Stony64/dotfiles-v3/archive/refs/tags/v3.6.5.zip)

---
