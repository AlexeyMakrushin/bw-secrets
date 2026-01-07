# bw-secrets: Changelog

## v0.3.0 (2026-01-05) — Refactoring Complete

### Fixed
- ✅ Infinite daemon restart loop — added fail counter (max 10 attempts)
- ✅ Session/login sync issues — all auth in Python, uses Keychain properly
- ✅ launchd label inconsistency — unified to `com.${USER}.bw-secrets`
- ✅ Session keys printed to terminal — all outputs suppressed
- ✅ Multiple shell scripts with duplicated logic — consolidated to Python CLI

### Changed
- `bw-unlock` → `bw-start` (starts daemon or reloads if running)
- `bw-suggest` → `bw-fields` (shows field suggestions for .envrc)
- `bw-reload` → use `bw-start` (same command works for reload)
- Added `bw-status` command to check daemon state
- Added `bw-stop` command to stop daemon
- GUI login dialog with tkinter (single window with all fields)
- Credentials stored in macOS Keychain
- Auto-start uses cached credentials when possible

### Removed
- `scripts/` directory (merged into `setup.sh` at root)
- `src/` directory (package now at `bw_secrets/`)
- Shell scripts: bw-unlock.sh, bw-start.sh, install-launchd.sh

### Structure
```
~/.secrets/
├── setup.sh              # One-command installation
├── bw_secrets/           # Python package
│   ├── cli.py            # All CLI commands
│   ├── daemon.py         # Background service
│   ├── gui.py            # Login dialog (tkinter)
│   └── bitwarden.py      # Vault operations
├── README.md
├── SKILL.md
└── .env
```

