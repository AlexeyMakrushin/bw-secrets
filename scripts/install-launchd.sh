#!/bin/bash
# Установка launchd агента для bw-secrets
# Автоматически определяет пути и создаёт plist

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PLIST_NAME="com.${USER}.bw-secrets.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo "Installing bw-secrets launchd agent..."
echo "Project: $PROJECT_DIR"

# Проверить что BW_SESSION сохранён в Keychain
if ! security find-generic-password -a "${USER}" -s "bw-secrets-session" -w >/dev/null 2>&1; then
    echo ""
    echo "ERROR: BW_SESSION not found in Keychain"
    echo ""
    echo "First run: bw-unlock"
    exit 1
fi

# Остановить существующий агент если запущен
LAUNCHD_LABEL="com.${USER}.bw-secrets"
if launchctl list | grep -q "$LAUNCHD_LABEL"; then
    echo "Stopping existing agent..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
fi

# Создать plist с правильными путями
cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PROJECT_DIR/scripts/bw-launch</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/bw-secrets.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/bw-secrets.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

echo "Created: $PLIST_DEST"

# Загрузить агент
launchctl load "$PLIST_DEST"
echo "Agent loaded"

# Подождать и проверить
sleep 2

if [ -S /tmp/bw-secrets.sock ]; then
    echo ""
    echo "SUCCESS! Socket created: /tmp/bw-secrets.sock"
    echo ""
    echo "Test with:"
    echo "  $PROJECT_DIR/.venv/bin/bw-list"
else
    echo ""
    echo "WARNING: Socket not created yet"
    echo "Check logs:"
    echo "  tail -20 /tmp/bw-secrets.err"
fi
