import json
import sys

from .client import send_command


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
