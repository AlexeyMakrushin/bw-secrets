# Changelog

## 2025-12-07 - Initial implementation

### Done
- Создана базовая структура проекта bw-secrets
- Реализован демон для загрузки секретов из Bitwarden в память
- Создан Unix socket сервер для доступа к секретам (asyncio)
- Реализованы CLI команды: bw-get, bw-suggest, bw-list, bw-reload, bw-secrets-daemon
- Создан Python клиент для программного доступа к секретам
- Настроен launchd для автозапуска демона при логине
- Добавлен .gitignore

### Decisions
- Использовать только stdlib (asyncio, json, subprocess, socket) без внешних зависимостей
- Хранить секреты только в RAM, не записывать на диск
- Unix socket с правами 600 для безопасности
- Текстовый протокол для простоты отладки

### Fixes
- Исправлена SyntaxError в daemon.py (global vault declaration)
- Создан скрипт start-daemon.sh для удобного запуска с BW_SESSION

### Testing
- Протестировано с реальным Bitwarden vault
- bw-get успешно возвращает секреты
- Демон запускается и работает корректно

### Next steps
- Настроить автозапуск через launchd
- Возможно добавить кэширование BW_SESSION в macOS Keychain
