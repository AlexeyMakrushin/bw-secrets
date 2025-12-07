# Настройка автозапуска bw-secrets через launchd

## Шаг 1: Сохранить BW_SESSION в macOS Keychain

```bash
# Разблокировать Bitwarden
export BW_SESSION=$(bw unlock --raw)

# Сохранить сессию в Keychain
cd ~/.secrets
./scripts/keychain-save-session.sh
```

Это сохранит `BW_SESSION` в macOS Keychain с именем `bw-secrets-session`.

## Шаг 2: Установить launchd агент

```bash
# Скопировать plist
cp ~/.secrets/launchd/com.amcr.bw-secrets.plist ~/Library/LaunchAgents/

# Загрузить агент
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist

# Проверить статус
launchctl list | grep bw-secrets
```

## Шаг 3: Проверить работу

```bash
# Проверить что socket создан
ls -la /tmp/bw-secrets.sock

# Проверить логи
tail -f /tmp/bw-secrets.out
tail -f /tmp/bw-secrets.err

# Проверить работу
cd ~/.secrets
.venv/bin/bw-list
```

## Управление

### Остановить демон
```bash
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

### Запустить снова
```bash
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

### Перезапустить
```bash
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

### Удалить автозапуск
```bash
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
rm ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

## Обновление BW_SESSION

Если Bitwarden сессия истекла:

```bash
# Разблокировать снова
export BW_SESSION=$(bw unlock --raw)

# Обновить в Keychain
cd ~/.secrets
./scripts/keychain-save-session.sh

# Перезапустить демон
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

## Безопасность

- `BW_SESSION` хранится в macOS Keychain (зашифрованно)
- Доступ к Keychain требует авторизации пользователя
- Демон запускается от имени текущего пользователя (не root)
- Socket файл имеет права 600 (только владелец)

## Troubleshooting

### Демон не запускается
Проверь логи:
```bash
cat /tmp/bw-secrets.err
```

Частые причины:
- BW_SESSION не сохранён в Keychain
- Сессия истекла
- Python venv не найден

### Socket не создаётся
```bash
# Проверь что процесс запущен
ps aux | grep bw-secrets-daemon

# Проверь логи
tail -20 /tmp/bw-secrets.out
tail -20 /tmp/bw-secrets.err
```

### Сессия истекает слишком быстро
Bitwarden сессии истекают по умолчанию через некоторое время.
Можно настроить более длительный timeout в Bitwarden settings.
