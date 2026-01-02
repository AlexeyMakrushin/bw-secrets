import base64
import json
import os
import subprocess
import sys

from .client import send_command


def get_project_dir() -> str:
    """Получить путь к ~/.secrets"""
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def configure_server():
    """Загрузить .env и настроить сервер Bitwarden."""
    project_dir = get_project_dir()
    env_file = os.path.join(project_dir, ".env")

    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    os.environ[key] = value

    bw_server = os.environ.get("BW_SERVER")
    if bw_server:
        subprocess.run(
            ["bw", "config", "server", bw_server],
            capture_output=True,
            stdin=subprocess.DEVNULL,
        )


def get_session() -> str:
    """Получить BW_SESSION из окружения или Keychain."""
    session = os.environ.get("BW_SESSION")
    if session:
        return session

    # Попробовать из Keychain
    try:
        result = subprocess.run(
            ["security", "find-generic-password",
             "-a", os.environ.get("USER", ""),
             "-s", "bw-secrets-session",
             "-w"],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass

    print("ERROR: BW_SESSION not found", file=sys.stderr)
    print("Run: bw-unlock", file=sys.stderr)
    sys.exit(1)


def cmd_get():
    """CLI команда: bw-get <item> [field]"""
    if len(sys.argv) < 2:
        print("Usage: bw-get <item> [field]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Examples:", file=sys.stderr)
        print("  bw-get google password", file=sys.stderr)
        print("  bw-get openai api-key", file=sys.stderr)
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
    """CLI команда: bw-suggest <item>"""
    if len(sys.argv) < 2:
        print("Usage: bw-suggest <item>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Shows all fields with suggested env variable names", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  bw-suggest google", file=sys.stderr)
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
    """CLI команда: bw-list"""
    response = send_command("LIST")

    if response.startswith("OK "):
        items = json.loads(response[3:])
        for item in items:
            print(item)
    else:
        print(response, file=sys.stderr)
        sys.exit(1)


def cmd_reload():
    """CLI команда: bw-reload"""
    response = send_command("RELOAD")

    if response.startswith("OK "):
        print(response[3:])
    else:
        print(response, file=sys.stderr)
        sys.exit(1)


def cmd_check():
    """CLI команда: bw-check [secrets.json]

    Проверяет что все секреты из файла существуют.
    НЕ выводит значения секретов.
    """
    path = sys.argv[1] if len(sys.argv) > 1 else "secrets.json"

    try:
        with open(path) as f:
            secrets = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    all_ok = True
    for var_name, config in secrets.items():
        # Прямое значение — проверяем только что не пустое
        if "value" in config:
            if config["value"]:
                print(f"✓ {var_name} (direct value)")
            else:
                print(f"✗ {var_name} (direct value) — EMPTY")
                all_ok = False
            continue

        # Загрузка из Bitwarden
        item = config.get("item")
        if not item:
            print(f"✗ {var_name} — no 'item' or 'value' specified")
            all_ok = False
            continue

        field = config.get("field", "password")

        # Проверяем существование через GET, но НЕ выводим значение
        response = send_command(f"GET {item} {field}")

        if response.startswith("OK "):
            print(f"✓ {var_name} ({item}/{field})")
        else:
            print(f"✗ {var_name} ({item}/{field}) — NOT FOUND")
            all_ok = False

    if not all_ok:
        sys.exit(1)


def cmd_add():
    """CLI команда: bw-add <item> [field=value ...]

    Создает новую запись в Bitwarden.
    После создания автоматически перезагружает кэш демона.

    Examples:
        bw-add telegram-bot password=abc123 api-key=xyz789
        bw-add google username=user@gmail.com password=secret
    """
    if len(sys.argv) < 3:
        print("Usage: bw-add <item> field=value [field=value ...]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Creates a new Bitwarden item with custom fields.", file=sys.stderr)
        print("", file=sys.stderr)
        print("Examples:", file=sys.stderr)
        print("  bw-add telegram-bot token=123456:ABC", file=sys.stderr)
        print("  bw-add openai api-key=sk-xxx", file=sys.stderr)
        print("  bw-add google username=user password=secret", file=sys.stderr)
        sys.exit(1)

    item_name = sys.argv[1]
    fields = {}

    for arg in sys.argv[2:]:
        if "=" not in arg:
            print(f"ERROR: Invalid field format: {arg}", file=sys.stderr)
            print("Expected: field=value", file=sys.stderr)
            sys.exit(1)
        key, value = arg.split("=", 1)
        fields[key] = value

    # Создаем объект записи для Bitwarden
    bw_item = {
        "organizationId": None,
        "collectionIds": None,
        "folderId": None,
        "type": 1,  # Login
        "name": item_name,
        "notes": None,
        "favorite": False,
        "fields": [],
        "login": {
            "uris": None,
            "username": None,
            "password": None,
            "totp": None,
        },
        "reprompt": 0,
    }

    # Распределяем поля
    for key, value in fields.items():
        if key == "password":
            bw_item["login"]["password"] = value
        elif key == "username":
            bw_item["login"]["username"] = value
        elif key == "uri" or key == "url":
            bw_item["login"]["uris"] = [{"match": None, "uri": value}]
        elif key == "notes":
            bw_item["notes"] = value
        else:
            # Custom field
            bw_item["fields"].append({
                "name": key,
                "value": value,
                "type": 0,  # Text
                "linkedId": None,
            })

    # Кодируем в base64 для bw create
    item_json = json.dumps(bw_item)
    item_b64 = base64.b64encode(item_json.encode()).decode()

    # Настроить сервер из .env
    configure_server()

    # Получаем сессию
    session = get_session()

    try:
        result = subprocess.run(
            ["bw", "create", "item", item_b64, "--session", session, "--nointeraction"],
            capture_output=True,
            text=True,
            timeout=30,
            stdin=subprocess.DEVNULL,
        )
        if result.returncode != 0:
            error_msg = result.stderr.strip() or result.stdout.strip() or "Unknown error"
            print(f"ERROR: {error_msg}", file=sys.stderr)
            sys.exit(1)

        if not result.stdout.strip():
            print("ERROR: Empty response from bw", file=sys.stderr)
            sys.exit(1)

        created = json.loads(result.stdout)
        print(f"✓ Created: {created['name']} (id: {created['id'][:8]}...)")

        # Синхронизируем vault
        subprocess.run(["bw", "sync", "--session", session], capture_output=True)

        # Перезагружаем кэш демона
        response = send_command("RELOAD")
        if response.startswith("OK "):
            print(f"✓ Daemon cache {response[3:]}")
        else:
            print(f"⚠ Daemon reload failed: {response}", file=sys.stderr)

    except subprocess.TimeoutExpired:
        print("ERROR: bw command timed out (session expired?)", file=sys.stderr)
        print("Run: bw-unlock", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("ERROR: bw CLI not found", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"ERROR: Invalid response from bw: {result.stdout}", file=sys.stderr)
        sys.exit(1)
