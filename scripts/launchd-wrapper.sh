#!/bin/bash
# Wrapper для запуска bw-secrets-daemon через launchd
# Получает BW_SESSION из macOS Keychain

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Получить BW_SESSION из Keychain
BW_SESSION=$(security find-generic-password \
    -a "${USER}" \
    -s "bw-secrets-session" \
    -w 2>/dev/null)

if [ -z "${BW_SESSION}" ]; then
    echo "ERROR: BW_SESSION not found in Keychain" >&2
    echo "First run: cd ~/.secrets && ./scripts/keychain-save-session.sh" >&2
    exit 1
fi

# Экспортировать и запустить демон
export BW_SESSION
cd "$PROJECT_DIR"
exec .venv/bin/bw-secrets-daemon
