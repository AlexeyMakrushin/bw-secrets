#!/bin/bash
# Разблокировка Bitwarden + сохранение сессии + перезапуск демона
# Поддерживает API key аутентификацию (BW_CLIENT_ID + BW_CLIENT_SECRET)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Загрузить .env
if [ -f "$PROJECT_DIR/.env" ]; then
    export $(grep -v '^#' "$PROJECT_DIR/.env" | grep -v '^$' | xargs)
fi

# Проверить текущий сервер
CURRENT_SERVER=$(bw config server 2>/dev/null)

# Если сервер отличается — logout и переконфигурировать
if [ -n "${BW_SERVER}" ] && [ "${CURRENT_SERVER}" != "${BW_SERVER}" ]; then
    echo "Switching server to: ${BW_SERVER}"
    bw logout 2>/dev/null
    bw config server "${BW_SERVER}"
fi

# Проверить статус
STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

# Функция логина с API key
api_login() {
    echo "Using API key authentication..."
    export BW_CLIENTID="${BW_CLIENT_ID}"
    export BW_CLIENTSECRET="${BW_CLIENT_SECRET}"
    bw login --apikey --raw
}

# Функция интерактивного логина
interactive_login() {
    bw login --raw
}

# Функция unlock (с паролем из env или интерактивно)
do_unlock() {
    if [ -n "${BW_PASSWORD}" ]; then
        echo "Using password from environment..."
        echo "${BW_PASSWORD}" | bw unlock --passwordenv BW_PASSWORD --raw
    else
        bw unlock --raw
    fi
}

# Логика аутентификации
if [ "$STATUS" = "unauthenticated" ]; then
    # Нужен login
    if [ -n "${BW_CLIENT_ID}" ] && [ -n "${BW_CLIENT_SECRET}" ]; then
        api_login
        # После API login нужен unlock
        echo "API login successful. Now unlocking vault..."
        export BW_SESSION=$(do_unlock)
    else
        export BW_SESSION=$(interactive_login)
    fi
elif [ "$STATUS" = "locked" ]; then
    # Уже залогинен, нужен только unlock
    export BW_SESSION=$(do_unlock)
else
    # Уже unlocked — просто получить сессию
    export BW_SESSION=$(do_unlock)
fi

if [ -z "${BW_SESSION}" ]; then
    echo "ERROR: Failed to get session" >&2
    exit 1
fi

# Сохранить в Keychain
"$SCRIPT_DIR/keychain-save-session.sh"

# Перезапустить демон
launchctl kickstart -k "gui/$(id -u)/com.amcr.bw-secrets"

echo "Done. Verify: ~/.secrets/.venv/bin/bw-list"
