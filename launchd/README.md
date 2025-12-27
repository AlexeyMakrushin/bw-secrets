# Автозапуск bw-secrets (launchd)

## Быстрая установка

```bash
# 1. Сохранить BW_SESSION в Keychain
export BW_SESSION=$(bw unlock --raw)
./scripts/keychain-save-session.sh

# 2. Установить и запустить
./scripts/install-launchd.sh
```

Готово! Демон запустится автоматически при каждом логине.

## Ручная установка

Если предпочитаешь вручную:

```bash
# Скопировать plist (проверь путь внутри!)
cp launchd/com.amcr.bw-secrets.plist ~/Library/LaunchAgents/

# Загрузить
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

## Управление

```bash
# Остановить
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist

# Запустить
launchctl load ~/Library/LaunchAgents/com.amcr.bw-secrets.plist

# Статус
launchctl list | grep bw-secrets

# Логи
tail -f /tmp/bw-secrets.out
tail -f /tmp/bw-secrets.err
```

## Удаление

```bash
launchctl unload ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
rm ~/Library/LaunchAgents/com.amcr.bw-secrets.plist
```

## Обновление BW_SESSION

Если сессия истекла:

```bash
export BW_SESSION=$(bw unlock --raw)
./scripts/keychain-save-session.sh
./scripts/install-launchd.sh  # перезапустит демон
```

## Troubleshooting

**Демон не запускается:**
```bash
cat /tmp/bw-secrets.err
```

**Socket не создаётся:**
```bash
ps aux | grep bw-secrets-daemon
```

Частые причины:
- BW_SESSION не в Keychain — запусти `keychain-save-session.sh`
- Сессия истекла — разблокируй Bitwarden снова
- Python venv не создан — запусти `uv sync`
