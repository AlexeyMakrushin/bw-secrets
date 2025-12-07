import socket
import sys

from . import SOCKET_PATH


def send_command(command: str) -> str:
    """Отправить команду демону через Unix socket."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(SOCKET_PATH)
        sock.sendall(f"{command}\n".encode())

        # Читаем ответ (до 64KB)
        response = sock.recv(65536).decode().strip()
        sock.close()

        return response

    except FileNotFoundError:
        print(
            f"ERROR: Cannot connect to daemon. Socket not found: {SOCKET_PATH}",
            file=sys.stderr
        )
        print("Is the daemon running? Try: bw-secrets-daemon", file=sys.stderr)
        sys.exit(1)

    except ConnectionRefusedError:
        print(
            f"ERROR: Cannot connect to daemon at {SOCKET_PATH}",
            file=sys.stderr
        )
        print("Is the daemon running? Try: bw-secrets-daemon", file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


def get_secret(item: str, field: str = "password") -> str:
    """Получить секрет из демона.

    Args:
        item: Имя записи в Bitwarden
        field: Имя поля (по умолчанию: password)

    Returns:
        Значение секрета

    Raises:
        ValueError: Если запись или поле не найдены
    """
    response = send_command(f"GET {item} {field}")

    if response.startswith("OK "):
        return response[3:]
    else:
        raise ValueError(response)
