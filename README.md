# bw-secrets

Демон для безопасного доступа к секретам из Bitwarden. Загружает vault в память один раз — отдаёт секреты мгновенно.

## Зачем?

- **Без .env файлов** — секреты не на диске, AI-агенты не прочитают случайно
- **Быстро** — vault в памяти, не нужно каждый раз расшифровывать
- **Просто** — `bw-get google password` вместо длинных команд bw

## Быстрый старт

```bash
# 1. Клонировать и установить
cd ~/.secrets
uv sync

# 2. Разблокировать Bitwarden и запустить демон
export BW_SESSION=$(bw unlock --raw)
.venv/bin/bw-secrets-daemon &

# 3. Готово! Проверить:
.venv/bin/bw-list
.venv/bin/bw-get google password
```

## Использование

### В shell-скриптах
```bash
PASSWORD=$(bw-get google password)
API_KEY=$(bw-get openai api-key)
```

### В Python
```python
from bw_secrets import get_secret

api_key = get_secret("openai", "api-key")
password = get_secret("google", "password")
```

### В Docker
```bash
docker run \
  -e OPENAI_API_KEY=$(bw-get openai api-key) \
  -e DB_PASSWORD=$(bw-get postgres password) \
  myapp
```

### Посмотреть доступные поля
```bash
bw-suggest google
# Выведет:
# GOOGLE_USERNAME=$(bw-get google username)
# GOOGLE_PASSWORD=$(bw-get google password)
```

## CLI команды

| Команда | Описание |
|---------|----------|
| `bw-get <item> [field]` | Получить секрет (field по умолчанию: password) |
| `bw-list` | Список всех записей |
| `bw-suggest <item>` | Показать все поля записи |
| `bw-reload` | Перезагрузить vault |
| `bw-secrets-daemon` | Запустить демон |

## Автозапуск (macOS)

Чтобы демон запускался автоматически при логине:

```bash
# 1. Сохранить сессию в Keychain
export BW_SESSION=$(bw unlock --raw)
./scripts/keychain-save-session.sh

# 2. Установить launchd агент
./scripts/install-launchd.sh
```

Подробнее: [launchd/README.md](launchd/README.md)

## Требования

- Python >= 3.11
- [uv](https://github.com/astral-sh/uv) — менеджер пакетов
- [bitwarden-cli](https://bitwarden.com/help/cli/) — `brew install bitwarden-cli`

## Безопасность

- Секреты хранятся только в RAM, не на диске
- Unix socket с правами 600 (только владелец)
- BW_SESSION в macOS Keychain (зашифрован)
- Инструкции для AI-агентов в [AGENTS.md](AGENTS.md)

## Структура

```
~/.secrets/
├── src/bw_secrets/     # Python пакет
├── scripts/            # Shell-скрипты
├── launchd/            # Автозапуск macOS
├── pyproject.toml
├── AGENTS.md           # Инструкции для AI
└── README.md
```
