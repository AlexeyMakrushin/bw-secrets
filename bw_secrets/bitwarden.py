import json
import os
import subprocess
import sys


def get_session() -> str:
    """Получить BW_SESSION из переменной окружения."""
    session = os.environ.get("BW_SESSION")
    if not session:
        print("ERROR: BW_SESSION not set", file=sys.stderr)
        print("Run: export BW_SESSION=$(bw unlock --raw)", file=sys.stderr)
        sys.exit(1)
    return session


def load_vault(session: str) -> dict:
    """Загрузить все записи из Bitwarden vault."""
    try:
        result = subprocess.run(
            ["bw", "list", "items", "--session", session],
            capture_output=True,
            text=True,
            check=True
        )
        items_json = json.loads(result.stdout)

        vault = {}
        for item in items_json:
            name, fields = parse_item(item)
            if name:
                vault[name] = fields

        return vault

    except subprocess.CalledProcessError as e:
        print(f"ERROR: Failed to load vault: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse vault JSON: {e}", file=sys.stderr)
        sys.exit(1)


def parse_item(item: dict) -> tuple[str, dict]:
    """Распарсить одну запись Bitwarden в удобный формат."""
    name = item.get("name")
    if not name:
        return None, {}

    fields = {}

    # Стандартные поля login
    if login := item.get("login"):
        if username := login.get("username"):
            fields["username"] = username
        if password := login.get("password"):
            fields["password"] = password
        if uris := login.get("uris"):
            if uris and len(uris) > 0:
                fields["uri"] = uris[0].get("uri", "")

    # Notes
    if notes := item.get("notes"):
        fields["notes"] = notes

    # Custom fields
    for field in item.get("fields", []):
        field_name = field.get("name")
        field_value = field.get("value")
        if field_name and field_value is not None:
            fields[field_name] = field_value

    return name, fields
