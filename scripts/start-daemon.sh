#!/bin/bash
# Скрипт для запуска bw-secrets daemon

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Проверить BW_SESSION
if [ -z "${BW_SESSION}" ]; then
    echo "ERROR: BW_SESSION not set"
    echo "Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Запустить демон
echo "Starting bw-secrets daemon..."
cd "$PROJECT_DIR"
export BW_SESSION
.venv/bin/bw-secrets-daemon
