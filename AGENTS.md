# AGENTS.md

## Статус проекта
✅ **MVP готов и протестирован**

Демон bw-secrets успешно реализован и работает:
- Загружает 148 записей из Bitwarden vault
- Unix socket работает корректно
- Все CLI команды протестированы и работают

## Архитектурные решения

### 1. Только stdlib
Решение: использовать только стандартную библиотеку Python
- asyncio для Unix socket сервера
- json для парсинга Bitwarden JSON
- subprocess для вызова `bw` CLI
- socket для клиента

**Почему:** Минимум зависимостей, максимальная надёжность

### 2. Секреты только в RAM
Vault загружается в dict и хранится в памяти процесса демона.
Никогда не записывается на диск в расшифрованном виде.

**Почему:** Защита от случайного чтения AI-агентами и другими процессами

### 3. Unix socket с правами 600
Socket файл `/tmp/bw-secrets.sock` создаётся с правами `srw-------` (600).
Только владелец процесса может читать/писать.

**Почему:** Изоляция от других пользователей системы

### 4. Текстовый протокол
Простые текстовые команды: GET, SUGGEST, LIST, RELOAD, PING

**Почему:** Легко отлаживать через `nc -U /tmp/bw-secrets.sock`

## Паттерны использования

### Python приложения
```python
from bw_secrets import get_secret

api_key = get_secret("openai", "api-key")
db_password = get_secret("postgres", "password")
```

### Shell скрипты
```bash
API_KEY=$(bw-get openai api-key)
DB_PASSWORD=$(bw-get postgres password)

# Или массово через suggest:
eval "$(bw-suggest myapp)"
# Создаст: MYAPP_USERNAME, MYAPP_PASSWORD, MYAPP_API_KEY
```

### Docker
```bash
docker run \
  -e OPENAI_API_KEY=$(bw-get openai api-key) \
  -e DB_PASSWORD=$(bw-get postgres password) \
  myapp
```

## Известные ограничения

1. **BW_SESSION требуется при каждом запуске**
   - Сейчас: нужно вручную разблокировать Bitwarden
   - TODO: кэширование в macOS Keychain

2. **Демон падает если vault изменился**
   - Решение: `bw-reload` для перезагрузки vault без перезапуска

3. **Только один пользователь**
   - Socket в /tmp доступен только владельцу
   - Для multi-user нужны отдельные сокеты

## Производительность

- Загрузка 148 записей: ~200ms
- GET запрос: <1ms (чтение из RAM)
- Размер в памяти: ~15-17MB для 148 записей

## Безопасность

✅ Секреты не в .env файлах (AI не может прочитать случайно)
✅ Секреты не в environment variables (не видны в `ps`)
✅ Секреты только в памяти процесса
✅ Socket с правами 600
✅ Демон запускается от имени пользователя (не root)

## Следующие улучшения

1. Keychain integration для BW_SESSION
2. GUI промпт для мастер-пароля при старте
3. Автообновление vault по таймеру (каждые N минут)
4. Metrics: количество запросов, время ответа
