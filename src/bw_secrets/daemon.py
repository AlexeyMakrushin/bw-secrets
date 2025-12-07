import asyncio
import json
import os
import signal
import sys

from . import SOCKET_PATH
from .bitwarden import get_session, load_vault


vault: dict = {}


def to_env_name(s: str) -> str:
    """Преобразовать строку в формат ENV переменной."""
    return s.upper().replace("-", "_").replace(" ", "_")


async def handle_client(reader, writer):
    """Обработать одно подключение клиента."""
    try:
        data = await reader.readline()
        request = data.decode().strip()

        if request:
            response = process_request(request)
        else:
            response = "ERROR empty request"

        writer.write(f"{response}\n".encode())
        await writer.drain()

    except Exception as e:
        error_msg = f"ERROR {str(e)}\n"
        writer.write(error_msg.encode())
        await writer.drain()

    finally:
        writer.close()
        await writer.wait_closed()


def process_request(request: str) -> str:
    """Обработать команду от клиента."""
    global vault

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
            available = ", ".join(vault[item].keys())
            return f"ERROR field not found: {field} (available: {available})"

        return f"OK {vault[item][field]}"

    elif cmd == "SUGGEST":
        if len(parts) < 2:
            return "ERROR usage: SUGGEST <item>"

        item = parts[1]

        if item not in vault:
            return f"ERROR item not found: {item}"

        suggestions = {}
        for field_name in vault[item].keys():
            env_var = f"{to_env_name(item)}_{to_env_name(field_name)}"
            suggestions[env_var] = f"bw-get {item} {field_name}"

        return f"OK {json.dumps(suggestions)}"

    elif cmd == "LIST":
        items = sorted(vault.keys())
        return f"OK {json.dumps(items)}"

    elif cmd == "RELOAD":
        try:
            session = get_session()
            vault = load_vault(session)
            return f"OK reloaded {len(vault)} items"
        except Exception as e:
            return f"ERROR reload failed: {str(e)}"

    return f"ERROR unknown command: {cmd}"


async def run_server():
    """Запустить Unix socket сервер."""
    global vault

    # Удалить старый socket если есть
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    # Загрузить vault
    session = get_session()
    vault = load_vault(session)
    print(f"Loaded {len(vault)} items from Bitwarden")

    # Запустить сервер
    server = await asyncio.start_unix_server(
        handle_client,
        path=SOCKET_PATH
    )

    # Установить права (только владелец)
    os.chmod(SOCKET_PATH, 0o600)

    print(f"Listening on {SOCKET_PATH}")

    # Обработка сигналов для graceful shutdown
    def handle_signal(signum, frame):
        print("\nShutting down...")
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    async with server:
        await server.serve_forever()


def main():
    """Entry point для bw-secrets-daemon."""
    try:
        asyncio.run(run_server())
    except KeyboardInterrupt:
        print("\nShutting down...")
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
