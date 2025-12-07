# bw-secrets

Демон для загрузки секретов из Bitwarden в память с доступом через Unix socket.

## Проблема

1. **Секреты в .env файлах** — небезопасно, AI-агенты могут прочитать
2. **Секреты в переменных окружения** — нужно загружать при каждом запуске терминала
3. **Прямые вызовы `bw get`** — медленно (каждый раз расшифровка)

## Решение

Демон, который:
- Загружает весь vault Bitwarden в память один раз при старте
- Отдаёт секреты через Unix socket по запросу
- Запускается автоматически при логине (launchd)
- Не сохраняет секреты на диск

## Архитектура

```
┌─────────────────────────────────────────────────────┐
│                    macOS Login                       │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│              launchd запускает демон                │
│         (требует BW_SESSION в Keychain)             │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│              bw-secrets-daemon (Python)             │
│  ┌───────────────────────────────────────────────┐  │
│  │     Память: весь vault Bitwarden (dict)       │  │
│  │     {item_name: {field: value, ...}, ...}     │  │
│  └───────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────┐  │
│  │  Unix Socket: /tmp/bw-secrets.sock            │  │
│  │  (права 600 — только владелец)                │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    ▼             ▼             ▼
┌────────┐  ┌──────────┐  ┌──────────────┐
│ Python │  │  Shell   │  │    Docker    │
│  App   │  │  Script  │  │  (при запуске)│
└────────┘  └──────────┘  └──────────────┘
```

## Использование

### Python-приложения
```python
from bw_secrets import get_secret

api_key = get_secret("openai", "api-key")
password = get_secret("google", "password")
```

### Shell-скрипты
```bash
PASSWORD=$(bw-get google password)
API_KEY=$(bw-get openai api-key)
```

### Docker
```bash
docker run \
  -e OPENAI_API_KEY=$(bw-get openai api-key) \
  -e DB_PASSWORD=$(bw-get postgres password) \
  myapp
```

### Генерация переменных
```bash
$ bw-suggest google

GOOGLE_USERNAME=$(bw-get google username)
GOOGLE_PASSWORD=$(bw-get google password)
GOOGLE_API_KEY=$(bw-get google api-key)
```

## Установка

```bash
# 1. Клонировать/создать проект
cd ~/.secrets

# 2. Установить через uv
uv pip install -e .

# 3. Настроить Bitwarden
bw login your-email@example.com
export BW_SESSION=$(bw unlock --raw)

# 4. Запустить демон (тест)
bw-secrets-daemon

# 5. Проверить
bw-get google password  # должен вернуть пароль

# 6. Установить автозапуск
cp launchd/com.amcr.bw-secrets.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

## Структура проекта

```
~/.secrets/
├── src/
│   └── bw_secrets/
│       ├── __init__.py        # Константы (SOCKET_PATH)
│       ├── daemon.py          # Unix socket сервер (asyncio)
│       ├── bitwarden.py       # Работа с bw CLI
│       ├── client.py          # Python-клиент
│       └── cli.py             # CLI команды
├── scripts/
│   └── bw-get                 # Shell-обёртка
├── launchd/
│   └── com.amcr.bw-secrets.plist
├── pyproject.toml
├── CLAUDE.md                  # Инструкции для AI
└── README.md
```

## CLI команды

| Команда | Описание |
|---------|----------|
| `bw-get <item> [field]` | Получить секрет (field по умолчанию: password) |
| `bw-suggest <item>` | Показать все поля с предложениями переменных |
| `bw-list` | Список всех записей (только имена) |
| `bw-reload` | Перезагрузить vault в демоне |
| `bw-secrets-daemon` | Запустить демон |

## Протокол socket

Текстовый протокол через Unix socket `/tmp/bw-secrets.sock`:

```
# Запрос → Ответ

GET google password
→ OK mysecretpassword

GET google api-key  
→ OK sk-xxx

SUGGEST google
→ OK {"GOOGLE_USERNAME":"...","GOOGLE_PASSWORD":"..."}

LIST
→ OK ["google","openai","anthropic"]

RELOAD
→ OK reloaded

PING
→ OK pong
```

## Безопасность

### Защита socket
- Права 600 — только владелец может читать/писать
- Файл в /tmp — удаляется при перезагрузке

### Секреты в памяти
- Vault загружается в dict, хранится только в RAM
- При остановке демона — данные исчезают
- Никаких файлов с расшифрованными секретами

### AI-агенты
- Секреты не в .env файлах — агент не может прочитать случайно
- CLAUDE.md содержит жёсткие инструкции не выводить секреты
- При соблюдении инструкций — секреты не попадают в контекст

## Зависимости

- Python >= 3.11
- Только stdlib (asyncio, json, subprocess, socket)
- bitwarden-cli (`bw`) — должен быть установлен

## TODO (после MVP)

- [ ] Кэширование BW_SESSION в Keychain
- [ ] GUI-промпт для мастер-пароля при старте
- [ ] Автообновление vault по таймеру
- [ ] Поддержка нескольких Bitwarden-аккаунтов
