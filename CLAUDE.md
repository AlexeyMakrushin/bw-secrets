# bw-secrets

Bitwarden secrets manager для macOS. Демон держит vault в памяти, CLI команды получают секреты.

## Архитектура

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  bw-get     │────▶│   daemon    │────▶│  Bitwarden  │
│  bw-list    │     │ (in-memory) │     │   Vault     │
│  bw-add     │     └─────────────┘     └─────────────┘
└─────────────┘            │
                           │ Unix socket
                           ▼
                    ~/.secrets/daemon.sock
```

**Компоненты:**
- `daemon.py` - держит vault в памяти, слушает Unix socket
- `cli.py` - CLI команды, общаются с демоном через socket
- `gui.py` - Tkinter диалоги для ввода пароля

**Хранение:**
- `.env` - конфигурация (BW_SERVER, BW_EMAIL)
- macOS Keychain - сессия (`bw-secrets-session`), мастер-пароль (`bw-secrets-master`)

## CLI Команды

### Основные (для пользователя)

| Команда | Описание | Пример |
|---------|----------|--------|
| `bw-get <item> [field]` | Получить секрет | `bw-get openrouter api` |
| `bw-list` | Список всех записей | `bw-list \| grep google` |
| `bw-suggest <item>` | Показать поля записи с env-именами | `bw-suggest openrouter` |
| `bw-add <item> field=value...` | Создать запись | `bw-add myapp token=xxx` |

### Управление демоном

| Команда | Описание |
|---------|----------|
| `bw-start` | Запустить демон. Если не запущен - показать GUI для пароля. Если запущен - sync + reload. |
| `bw-stop` | Остановить демон |
| `bw-status` | Статус демона (running/stopped, server, email, items count) |

### Внутренние (не для пользователя)

| Команда | Описание |
|---------|----------|
| `bw-launch` | Для launchd. Пытается запустить с keychain, если нет - GUI. Fail counter до 10. |
| `bw-secrets-daemon` | Сам демон. Не вызывать напрямую. |

## Логика bw-start

```
bw-start
    │
    ▼
Демон запущен? ──yes──▶ RELOAD (sync + перезагрузка данных)
    │                         │
    no                        ▼
    │                    Вывод: "reloaded N items"
    ▼
Показать GUI для ввода пароля
    │
    ▼
Аутентификация успешна? ──no──▶ Показать ошибку, повторить (до 10 раз)
    │
    yes
    │
    ▼
Сохранить в Keychain (session + master password)
    │
    ▼
Запустить демон
    │
    ▼
Показать notification "Daemon started"
```

## Логика bw-launch (для launchd)

```
bw-launch
    │
    ▼
Есть пароль в Keychain? ──no──▶ Показать GUI
    │                                │
    yes                              ▼
    │                          (как в bw-start)
    ▼
Попробовать unlock с паролем из Keychain
    │
    ▼
Успех? ──no──▶ Показать GUI
    │
    yes
    │
    ▼
Запустить демон (exec, заменяет процесс)
    │
    ▼
При ошибке: fail counter++
Если fail counter >= 10: остановить launchd, показать alert
```

## Логика автообновления (daemon)

```
Каждый час:
    │
    ▼
Есть пароль в Keychain? ──no──▶ Пропустить
    │
    yes
    │
    ▼
bw sync + перезагрузка vault в память
```

## GUI: Окно входа

**Размер:** 420x300, фиксированный, по центру экрана

**Элементы (сверху вниз):**
1. Заголовок: "Bitwarden Login" (bold, 16pt)
2. Статус-сообщение:
   - Нейтральное: "Enter your master password" (серый)
   - Ошибка: "Wrong password. 9 attempt(s) left." (красный)
3. Server URL: текстовое поле
4. Email: текстовое поле
5. Password: текстовое поле + кнопка Show/Hide
6. Кнопки: Cancel (слева), Login (справа)

**Поведение:**
- Фокус: если есть server+email → фокус на password
- Enter → Login
- Escape → Cancel
- Попыток: 10
- После Cancel: exit без ошибки (не считается как fail)

**Требования к полю пароля:**
- Маска: звёздочки (*)
- Кнопка Show/Hide рядом с полем (справа)
- При Show: показать пароль, кнопка → "Hide"
- При Hide: скрыть пароль, кнопка → "Show"

**Стиль:**
- macOS native (ttk theme "aqua")
- Шрифт: SF Pro Display
- Окно поверх других при появлении

## Файлы проекта

```
~/.secrets/
├── .env                 # BW_SERVER, BW_EMAIL
├── .venv/               # Python virtualenv
├── bw_secrets/          # Исходный код
│   ├── __init__.py
│   ├── cli.py           # CLI команды
│   ├── daemon.py        # Демон
│   └── gui.py           # Tkinter GUI
├── pyproject.toml       # Зависимости, entry points
├── setup.sh             # Установщик
└── daemon.sock          # Unix socket (runtime)
```

## launchd

**Plist:** `~/Library/LaunchAgents/com.$USER.bw-secrets.plist`

- RunAtLoad: true (запуск при входе)
- KeepAlive: true (перезапуск при падении)
- Команда: `bw-launch`

## Keyboard Shortcut

**Automator workflow:** `~/Library/Services/bw-start.workflow`
- Quick Action, без входных данных
- Запускает: `~/.secrets/.venv/bin/bw-start`

**Shortcut по умолчанию:** Ctrl+Opt+Cmd+B (настраивается при установке)

## Правила для Claude

1. Не менять логику без согласования
2. Не переименовывать команды
3. Не добавлять новые команды без согласования
4. GUI: строго по спецификации выше
5. Перед изменениями - показать план и спросить
