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
- Протестировано с реальным Bitwarden vault (148 записей)
- bw-get успешно возвращает секреты
- bw-suggest корректно формирует ENV переменные
- Демон запускается и работает корректно

### Автозапуск (launchd)
- Созданы скрипты для работы с macOS Keychain:
  - keychain-save-session.sh - сохранить BW_SESSION
  - keychain-get-session.sh - получить BW_SESSION
  - launchd-wrapper.sh - wrapper для автозапуска
- Обновлён com.amcr.bw-secrets.plist для использования wrapper
- Добавлена документация launchd/README.md

### Claude AI Integration
- Создан skill (.claude/skills/bw-secrets.md) для безопасной работы с секретами
- Skill включает:
  - Инструкции когда использовать
  - Примеры безопасных паттернов
  - Правила безопасности (что НИКОГДА нельзя делать)
  - Примеры для Docker, Python, shell скриптов

### Документация
- Обновлён README.md с актуальными инструкциями
- Создан AGENTS.md с архитектурными решениями
- Добавлены примеры использования во всех контекстах

### Next steps
- Возможно добавить GUI промпт для мастер-пароля
- Автообновление vault по таймеру
- Метрики использования
