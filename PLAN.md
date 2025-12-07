# План реализации: bw-secrets

## Цель
Демон для загрузки секретов из Bitwarden в память с доступом через Unix socket.
Секреты никогда не сохраняются на диск в открытом виде.

## Порядок реализации

### Шаг 1: pyproject.toml
```toml
[project]
name = "bw-secrets"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = []

[project.scripts]
bw-get = "bw_secrets.cli:cmd_get"
bw-suggest = "bw_secrets.cli:cmd_suggest"
bw-reload = "bw_secrets.cli:cmd_reload"
bw-list = "bw_secrets.cli:cmd_list"
bw-secrets-daemon = "bw_secrets.daemon:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

### Шаг 2: src/bw_secrets/__init__.py
```python
SOCKET_PATH = "/tmp/bw-secrets.sock"
VERSION = "0.1.0"
```

### Шаг 3: src/bw_secrets/bitwarden.py

Функции:
- `get_session() -> str` — получить BW_SESSION из env
- `load_vault(session: str) -> dict` — загрузить все записи
- `parse_item(item: dict) -> dict` — распарсить одну запись

Формат vault dict:
```python
{
    "google": {
        "username": "user@gmail.com",
        "password": "secret123",
        "api-key": "sk-xxx",  # custom field
        "notes": "...",
        "uri": "https://google.com"
    },
    "openai": {
        "password": "sk-...",
        ...
    }
}
```

Парсинг item JSON от bw:
```python
def parse_item(item: dict) -> tuple[str, dict]:
    name = item["name"]
    fields = {}
    
    # Стандартные поля login
    if login := item.get("login"):
        if login.get("username"):
            fields["username"] = login["username"]
        if login.get("password"):
            fields["password"] = login["password"]
        if login.get("uris"):
            fields["uri"] = login["uris"][0]["uri"]
    
    # Notes
    if item.get("notes"):
        fields["notes"] = item["notes"]
    
    # Custom fields
    for field in item.get("fields", []):
        fields[field["name"]] = field["value"]
    
    return name, fields
```

### Шаг 4: src/bw_secrets/daemon.py

Asyncio Unix socket сервер:

```python
import asyncio
import os
import signal
from . import SOCKET_PATH
from .bitwarden import get_session, load_vault

vault: dict = {}

async def handle_client(reader, writer):
    try:
        data = await reader.readline()
        request = data.decode().strip()
        response = process_request(request)
        writer.write(f"{response}\n".encode())
        await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()

def process_request(request: str) -> str:
    parts = request.split()
    if not parts:
        return "ERROR empty request"
    
    cmd = parts[0].upper()
    
    if cmd == "PING":
        return "OK pong"
    
    elif cmd == "GET":
        if len(parts) < 2:
            return "ERROR usage: GET <item> [field]"
        item = parts[1]
        field = parts[2] if len(parts) > 2 else "password"
        
        if item not in vault:
            return f"ERROR item not found: {item}"
        if field not in vault[item]:
            return f"ERROR field not found: {field}"
        
        return f"OK {vault[item][field]}"
    
    elif cmd == "SUGGEST":
        # ... возвращает JSON с предложениями
    
    elif cmd == "LIST":
        # ... возвращает список имён
    
    elif cmd == "RELOAD":
        # ... перезагружает vault
    
    return f"ERROR unknown command: {cmd}"

async def run_server():
    global vault
    
    # Удалить старый socket если есть
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    
    # Загрузить vault
    session = get_session()
    vault = load_vault(session)
    print(f"Loaded {len(vault)} items")
    
    # Запустить сервер
    server = await asyncio.start_unix_server(
        handle_client,
        path=SOCKET_PATH
    )
    
    # Установить права
    os.chmod(SOCKET_PATH, 0o600)
    
    print(f"Listening on {SOCKET_PATH}")
    
    async with server:
        await server.serve_forever()

def main():
    asyncio.run(run_server())
```

### Шаг 5: src/bw_secrets/client.py

```python
import socket
from . import SOCKET_PATH

def send_command(command: str) -> str:
    """Отправить команду демону, получить ответ."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(SOCKET_PATH)
        sock.sendall(f"{command}\n".encode())
        response = sock.recv(65536).decode().strip()
        return response
    finally:
        sock.close()

def get_secret(item: str, field: str = "password") -> str:
    """Получить секрет из демона."""
    response = send_command(f"GET {item} {field}")
    if response.startswith("OK "):
        return response[3:]
    raise ValueError(response)
```

### Шаг 6: src/bw_secrets/cli.py

```python
import sys
import json
from .client import send_command

def cmd_get():
    if len(sys.argv) < 2:
        print("Usage: bw-get <item> [field]", file=sys.stderr)
        sys.exit(1)
    
    item = sys.argv[1]
    field = sys.argv[2] if len(sys.argv) > 2 else "password"
    
    response = send_command(f"GET {item} {field}")
    if response.startswith("OK "):
        print(response[3:])
    else:
        print(response, file=sys.stderr)
        sys.exit(1)

def cmd_suggest():
    if len(sys.argv) < 2:
        print("Usage: bw-suggest <item>", file=sys.stderr)
        sys.exit(1)
    
    item = sys.argv[1]
    response = send_command(f"SUGGEST {item}")
    
    if response.startswith("OK "):
        data = json.loads(response[3:])
        for var, cmd in data.items():
            print(f"{var}=$({cmd})")
    else:
        print(response, file=sys.stderr)
        sys.exit(1)

def cmd_list():
    response = send_command("LIST")
    if response.startswith("OK "):
        items = json.loads(response[3:])
        for item in items:
            print(item)
    else:
        print(response, file=sys.stderr)
        sys.exit(1)

def cmd_reload():
    response = send_command("RELOAD")
    print(response)
```

### Шаг 7: scripts/bw-get

```bash
#!/bin/bash
python3 -m bw_secrets.cli get "$@"
```

### Шаг 8: launchd/com.amcr.bw-secrets.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.amcr.bw-secrets</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/Users/alexeymakrushin/.local/bin/bw-secrets-daemon</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/tmp/bw-secrets.out</string>
    
    <key>StandardErrorPath</key>
    <string>/tmp/bw-secrets.err</string>
</dict>
</plist>
```

### Шаг 9: CLAUDE.md
(уже создан — инструкции безопасности для AI)

### Шаг 10: README.md
(уже создан — документация)

## Тестирование

```bash
# 1. Установить
cd ~/.secrets
uv pip install -e .

# 2. Получить сессию Bitwarden
export BW_SESSION=$(bw unlock --raw)

# 3. Запустить демон в фоне
bw-secrets-daemon &

# 4. Проверить
bw-list
bw-get <item_name> password
bw-suggest <item_name>

# 5. Остановить
pkill -f bw-secrets-daemon
```

## Важные детали реализации

### Обработка ошибок
- Демон не запущен → понятное сообщение "Cannot connect to daemon"
- Запись не найдена → "ERROR item not found: xxx"
- Поле не найдено → "ERROR field not found: xxx"
- Bitwarden locked → "ERROR BW_SESSION not set or invalid"

### Graceful shutdown
```python
def handle_signal(signum, frame):
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)
```

### SUGGEST формат
Преобразование имён:
- `my-app` → `MY_APP`
- `api-key` → `API_KEY`
- `myApp` → `MYAPP` (просто upper)

```python
def to_env_name(s: str) -> str:
    return s.upper().replace("-", "_")
```
