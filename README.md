# bw-secrets

Демон для безопасного доступа к секретам из Bitwarden. Загружает vault в память один раз — отдаёт секреты мгновенно.

## Зачем?

- **Без .env файлов** — секреты не на диске
- **Быстро** — vault в памяти, не нужно каждый раз расшифровывать
- **Просто** — `bw-get google password` вместо длинных команд bw
- **Универсально** — работает с Docker, Python, Node, любым языком через direnv

## Быстрый старт

```bash
# 1. Установить
cd ~/.secrets
uv sync

# 2. Настроить сервер (для self-hosted)
cp .env.example .env
# Отредактировать BW_SERVER

# 3. Добавить алиасы в .zshrc
echo 'alias bw-unlock="~/.secrets/scripts/bw-unlock.sh"' >> ~/.zshrc
source ~/.zshrc

# 4. Разблокировать и запустить демон
bw-unlock

# 5. Проверить
~/.secrets/.venv/bin/bw-list
```

## Использование: direnv

Рекомендуемый способ — через direnv:

```bash
# Установить direnv (один раз)
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

В каждом проекте создать `.envrc`:

```bash
export POSTGRES_PASSWORD=$(~/.secrets/.venv/bin/bw-get myapp password)
export API_KEY=$(~/.secrets/.venv/bin/bw-get myapp api-key)
```

```bash
direnv allow     # разрешить (один раз)
cd project/      # переменные загружаются автоматически
docker compose up
```

### В скриптах/cron

```bash
#!/bin/bash
source /path/to/project/.envrc
docker compose up -d
```

## CLI команды

| Команда | Описание |
|---------|----------|
| `bw-get <item> [field]` | Получить секрет (field по умолчанию: password) |
| `bw-list` | Список всех записей |
| `bw-suggest <item>` | Показать все поля записи |
| `bw-add <item> field=value ...` | Создать новую запись |
| `bw-reload` | Перезагрузить vault |

### Создание записи

```bash
bw-add telegram-bot token=123456:ABC
bw-add openai api-key=sk-xxx username=user@example.com
```

Стандартные поля: `password`, `username`, `uri`, `notes`.
Остальные сохраняются как custom fields.

## Конфигурация (.env)

```bash
# Сервер (для self-hosted Vaultwarden)
BW_SERVER=https://vault.example.com

# API Key (опционально — для автоматического логина)
BW_CLIENT_ID=user.xxx
BW_CLIENT_SECRET=xxx

# Master password (опционально — для полной автоматизации)
BW_PASSWORD=xxx
```

## Автозапуск (macOS launchd)

Чтобы демон запускался автоматически при логине:

```bash
# Установить launchd агент
./scripts/install-launchd.sh
```

### Управление

```bash
# Статус
launchctl list | grep bw-secrets

# Логи
tail -f /tmp/bw-secrets.err

# Остановить
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist

# Запустить
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

### Удаление

```bash
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
rm ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

### Обновление сессии

Если сессия истекла:

```bash
bw-unlock
```

## Требования

- Python >= 3.11
- [uv](https://github.com/astral-sh/uv) — менеджер пакетов
- [bitwarden-cli](https://bitwarden.com/help/cli/) — `brew install bitwarden-cli`
- [direnv](https://direnv.net/) — `brew install direnv` (опционально)

## Безопасность

- Секреты хранятся только в RAM, не на диске
- Unix socket с правами 600 (только владелец)
- BW_SESSION в macOS Keychain (зашифрован)

## Структура

```
~/.secrets/
├── src/bw_secrets/     # Python пакет
├── scripts/            # Shell-скрипты
├── launchd/            # Автозапуск macOS
└── pyproject.toml
```
