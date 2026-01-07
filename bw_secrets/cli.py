"""CLI commands for bw-secrets."""

import base64
import json
import os
import socket
import subprocess
import sys
import time

from . import SOCKET_PATH, VERSION


def get_project_dir() -> str:
    """Get path to ~/.secrets"""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_env() -> dict:
    """Load .env file and return as dict."""
    project_dir = get_project_dir()
    env_file = os.path.join(project_dir, ".env")
    env = {}

    if os.path.exists(env_file):
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, value = line.split("=", 1)
                    env[key] = value

    return env


def save_env(env: dict):
    """Save dict to .env file."""
    project_dir = get_project_dir()
    env_file = os.path.join(project_dir, ".env")

    lines = [
        "# bw-secrets configuration",
        "# Secrets are stored in macOS Keychain, NOT in this file",
        "",
    ]

    for key, value in env.items():
        if key == "BW_SERVER":
            lines.append("# Bitwarden server URL")
        elif key == "BW_EMAIL":
            lines.append("")
            lines.append("# User email (for login)")
        lines.append(f"{key}={value}")

    with open(env_file, "w") as f:
        f.write("\n".join(lines) + "\n")


def _send_to_socket(command: str) -> str:
    """Send command to daemon socket."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(SOCKET_PATH)
    sock.sendall(f"{command}\n".encode())
    response = sock.recv(65536).decode().strip()
    sock.close()
    return response


def try_auto_start() -> bool:
    """Try to auto-start daemon with GUI dialog.

    Returns True if daemon started successfully, False otherwise.
    """
    from .gui import show_login_dialog

    env = load_env()
    vault = env.get("BW_SERVER", "https://vault.bitwarden.com")
    email = env.get("BW_EMAIL", "")
    error_msg = ""

    # First try with cached password from keychain
    password = keychain_get("bw-secrets-master")
    if password:
        bw_configure_server(vault)
        status = bw_status()

        session = None
        if status == "unlocked":
            session = keychain_get("bw-secrets-session")
        elif status == "locked":
            session, _ = bw_unlock(password)
        elif status == "unauthenticated":
            session, _ = bw_login(email, password)

        if session:
            keychain_set("bw-secrets-session", session)
            if start_daemon_process(session):
                return True

    # Keychain didn't work, show GUI
    max_attempts = 10
    for attempt in range(1, max_attempts + 1):
        result = show_login_dialog(vault=vault, email=email, error_msg=error_msg)

        if not result:
            return False

        vault = result["vault"]
        email = result["email"]
        password = result["password"]

        # Update .env if changed
        if vault != env.get("BW_SERVER") or email != env.get("BW_EMAIL"):
            env["BW_SERVER"] = vault
            env["BW_EMAIL"] = email
            save_env(env)

        # Configure and authenticate
        bw_configure_server(vault)
        status = bw_status()

        if status == "unauthenticated":
            session, auth_error = bw_login(email, password)
        else:
            session, auth_error = bw_unlock(password)

        if session:
            keychain_set("bw-secrets-session", session)
            keychain_set("bw-secrets-master", password)
            if start_daemon_process(session):
                return True

        remaining = max_attempts - attempt
        if remaining > 0:
            error_msg = f"{auth_error}. {remaining} attempt(s) left."
        else:
            error_msg = f"{auth_error}. No attempts left."

    return False


def can_show_gui() -> bool:
    """Check if we can show GUI dialogs on macOS."""
    # Always allow GUI on macOS - Tkinter works with window server
    # Only disable if explicitly set (e.g., in SSH sessions without forwarding)
    if os.environ.get("BW_NO_GUI") == "1":
        return False
    # Check if we're on macOS
    if sys.platform == "darwin":
        return True
    # On other platforms, check for display
    return bool(os.environ.get("DISPLAY"))


def send_command(command: str) -> str:
    """Send command to daemon via Unix socket.

    If daemon is not running, try to start it with GUI dialog.
    """
    try:
        return _send_to_socket(command)
    except FileNotFoundError:
        pass
    except ConnectionRefusedError:
        pass

    # Daemon not running - try to auto-start
    # On macOS, always try GUI (works even without TTY)
    # Can be disabled with BW_NO_GUI=1
    if can_show_gui() or sys.stdout.isatty():
        if try_auto_start():
            try:
                return _send_to_socket(command)
            except Exception:
                pass

    # Show error
    print(f"ERROR: Socket not found: {SOCKET_PATH}", file=sys.stderr)
    print("Run: bw-start", file=sys.stderr)
    sys.exit(1)


def configure_server():
    """Load .env and configure Bitwarden server."""
    env = load_env()

    for key, value in env.items():
        os.environ[key] = value

    bw_server = os.environ.get("BW_SERVER")
    if bw_server:
        subprocess.run(
            ["bw", "config", "server", bw_server],
            capture_output=True,
            stdin=subprocess.DEVNULL,
        )


def get_session() -> str:
    """Get BW_SESSION from environment or Keychain."""
    session = os.environ.get("BW_SESSION")
    if session:
        return session

    # Try from Keychain
    try:
        result = subprocess.run(
            [
                "security",
                "find-generic-password",
                "-a",
                os.environ.get("USER", ""),
                "-s",
                "bw-secrets-session",
                "-w",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    except Exception:
        pass

    print("ERROR: BW_SESSION not found", file=sys.stderr)
    print("Run: bw-start", file=sys.stderr)
    sys.exit(1)


def cmd_get():
    """CLI command: bw-get <item> [field]"""
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


def cmd_fields():
    """CLI command: bw-fields <item>

    Shows all fields for an entry with suggested env variable names.
    (Renamed from bw-suggest)
    """
    if len(sys.argv) < 2:
        print("Usage: bw-fields <item>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Shows all fields with suggested env variable names", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  bw-fields google", file=sys.stderr)
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


# Keep old name for backwards compatibility
cmd_suggest = cmd_fields


def cmd_list():
    """CLI command: bw-list"""
    response = send_command("LIST")

    if response.startswith("OK "):
        items = json.loads(response[3:])
        for item in items:
            print(item)
    else:
        print(response, file=sys.stderr)
        sys.exit(1)


def cmd_reload():
    """CLI command: bw-reload (deprecated, use bw-start)"""
    response = send_command("RELOAD")

    if response.startswith("OK "):
        print(response[3:])
    else:
        print(response, file=sys.stderr)
        sys.exit(1)


def cmd_status():
    """CLI command: bw-status

    Shows daemon status, connection info, and item count.
    """
    env = load_env()
    server = env.get("BW_SERVER", "https://vault.bitwarden.com")
    email = env.get("BW_EMAIL", "")

    # Check if socket exists
    if not os.path.exists(SOCKET_PATH):
        print("Status: stopped")
        print(f"Socket: {SOCKET_PATH} (not found)")
        print(f"Server: {server}")
        print(f"User: {email}")
        sys.exit(1)

    # Try to ping daemon
    try:
        response = _send_to_socket("PING")
        if response == "OK pong":
            # Get item count
            list_response = _send_to_socket("LIST")
            if list_response.startswith("OK "):
                items = json.loads(list_response[3:])
                item_count = len(items)
            else:
                item_count = "?"

            print("Status: running")
            print(f"Socket: {SOCKET_PATH}")
            print(f"Server: {server}")
            print(f"User: {email}")
            print(f"Items: {item_count}")
            print(f"Version: {VERSION}")
        else:
            print("Status: error")
            print(f"Response: {response}")
            sys.exit(1)
    except Exception as e:
        print("Status: error")
        print(f"Error: {e}")
        sys.exit(1)


def cmd_add():
    """CLI command: bw-add <item> [field=value ...]

    Creates a new Bitwarden entry.
    After creation, automatically reloads daemon cache.

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

    # Create Bitwarden item object
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

    # Distribute fields
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
            bw_item["fields"].append(
                {
                    "name": key,
                    "value": value,
                    "type": 0,  # Text
                    "linkedId": None,
                }
            )

    # Encode to base64 for bw create
    item_json = json.dumps(bw_item)
    item_b64 = base64.b64encode(item_json.encode()).decode()

    # Configure server from .env
    configure_server()

    # Get session
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
        print(f"Created: {created['name']} (id: {created['id'][:8]}...)")

        # Sync vault
        subprocess.run(["bw", "sync", "--session", session], capture_output=True)

        # Reload daemon cache
        response = send_command("RELOAD")
        if response.startswith("OK "):
            print(f"Cache {response[3:]}")
        else:
            print(f"Warning: Cache reload failed: {response}", file=sys.stderr)

    except subprocess.TimeoutExpired:
        print("ERROR: bw command timed out (session expired?)", file=sys.stderr)
        print("Run: bw-start", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("ERROR: bw CLI not found", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError:
        print(f"ERROR: Invalid response from bw: {result.stdout}", file=sys.stderr)
        sys.exit(1)


# =============================================================================
# Daemon management commands
# =============================================================================

FAIL_COUNT_FILE = "/tmp/bw-secrets.fail-count"
MAX_FAILURES = 10


def keychain_get(service: str) -> str | None:
    """Get value from macOS Keychain."""
    try:
        result = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
             "-s", service, "-w"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def keychain_set(service: str, value: str):
    """Save value to macOS Keychain."""
    user = os.environ.get("USER", "")
    # Try update first, then add
    subprocess.run(
        ["security", "add-generic-password", "-a", user, "-s", service, "-w", value, "-U"],
        capture_output=True
    )


def bw_status() -> str:
    """Get Bitwarden CLI status: unauthenticated, locked, unlocked."""
    try:
        result = subprocess.run(["bw", "status"], capture_output=True, text=True)
        data = json.loads(result.stdout)
        return data.get("status", "unknown")
    except Exception:
        return "unknown"


def bw_configure_server(server: str):
    """Configure Bitwarden server if needed (only when unauthenticated)."""
    try:
        # Only configure server if not logged in
        status = subprocess.run(["bw", "status"], capture_output=True, text=True)
        status_data = json.loads(status.stdout)
        if status_data.get("status") != "unauthenticated":
            return  # Already logged in, don't touch server config

        result = subprocess.run(["bw", "config", "server"], capture_output=True, text=True)
        current = result.stdout.strip()
        if current != server:
            subprocess.run(["bw", "config", "server", server], capture_output=True)
    except Exception:
        pass


def bw_login(email: str, password: str) -> tuple[str | None, str]:
    """Login to Bitwarden, return (session_key, error_message)."""
    try:
        result = subprocess.run(
            ["bw", "login", email, "--raw"],
            input=password + "\n",
            capture_output=True, text=True, timeout=60
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip(), ""

        # Parse error
        error = result.stderr.lower() if result.stderr else ""
        if "username or password" in error or "invalid" in error:
            return None, "Wrong email or password"
        elif "not found" in error or "unable to resolve" in error or "enotfound" in error:
            return None, "Server not found. Check URL."
        elif "network" in error or "connect" in error:
            return None, "Network error. Check connection."
        else:
            return None, "Login failed. Check credentials."
    except subprocess.TimeoutExpired:
        return None, "Timeout. Server not responding."
    except Exception:
        return None, "Login failed"


def bw_unlock(password: str) -> tuple[str | None, str]:
    """Unlock Bitwarden vault, return (session_key, error_message)."""
    try:
        env = os.environ.copy()
        env["BW_PASSWORD"] = password
        result = subprocess.run(
            ["bw", "unlock", "--passwordenv", "BW_PASSWORD", "--raw"],
            capture_output=True, text=True, timeout=60, env=env
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip(), ""

        # Parse error - check both stderr and stdout
        error = (result.stderr + " " + result.stdout).lower()
        if "invalid" in error or "password" in error or "master" in error:
            return None, "Wrong password"
        elif "not logged in" in error or "unauthenticated" in error:
            return None, "Not logged in. Check email."
        else:
            return None, "Unlock failed"
    except subprocess.TimeoutExpired:
        return None, "Timeout. Server not responding."
    except Exception:
        return None, "Unlock failed"


def start_daemon_process(session: str) -> bool:
    """Start the daemon process with given session."""
    project_dir = get_project_dir()
    daemon_path = os.path.join(project_dir, ".venv", "bin", "bw-secrets-daemon")

    # Kill existing daemon
    subprocess.run(["pkill", "-f", "bw-secrets-daemon"], capture_output=True)
    time.sleep(0.5)

    # Remove old socket
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    # Start new daemon
    env = os.environ.copy()
    env["BW_SESSION"] = session

    subprocess.Popen(
        [daemon_path],
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True
    )

    # Wait for socket
    for _ in range(20):
        if os.path.exists(SOCKET_PATH):
            return True
        time.sleep(0.25)

    return False


def cmd_start():
    """CLI command: bw-start

    Smart start:
    - If daemon is running: sync and reload data
    - If daemon is not running: show GUI, authenticate, start daemon
    """
    from .gui import show_login_dialog, show_notification

    # Check if daemon is already running
    if os.path.exists(SOCKET_PATH):
        try:
            response = _send_to_socket("RELOAD")
            if response.startswith("OK "):
                print(response[3:])
                return
        except Exception:
            # Socket exists but daemon not responding - continue to restart
            pass

    # Daemon not running - show GUI and start
    env = load_env()
    server = env.get("BW_SERVER", "https://vault.bitwarden.com")
    email = env.get("BW_EMAIL", "")
    session = None
    error_msg = ""

    # Configure server
    bw_configure_server(server)

    # Show GUI for password - max 10 attempts
    max_attempts = 10
    for attempt in range(1, max_attempts + 1):
        result = show_login_dialog(vault=server, email=email, error_msg=error_msg)

        if not result:
            print("Cancelled", file=sys.stderr)
            sys.exit(1)

        server = result["vault"]
        email = result["email"]
        password = result["password"]

        # Update .env if changed
        if server != env.get("BW_SERVER") or email != env.get("BW_EMAIL"):
            env["BW_SERVER"] = server
            env["BW_EMAIL"] = email
            save_env(env)

        # Configure server
        bw_configure_server(server)

        # Try to authenticate
        status = bw_status()
        if status == "unauthenticated":
            session, auth_error = bw_login(email, password)
        else:
            session, auth_error = bw_unlock(password)

        if session:
            break

        remaining = max_attempts - attempt
        if remaining > 0:
            error_msg = f"{auth_error}. {remaining} attempt(s) left."
        else:
            error_msg = f"{auth_error}. No attempts left."

    if not session:
        print("ERROR: Failed to authenticate", file=sys.stderr)
        sys.exit(1)

    # Save credentials to Keychain
    keychain_set("bw-secrets-session", session)
    keychain_set("bw-secrets-master", password)

    # Stop existing daemon if running
    subprocess.run(["pkill", "-f", "bw-secrets-daemon"], capture_output=True)
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)
    time.sleep(0.5)

    # Start daemon
    if start_daemon_process(session):
        print("Daemon started")
        print(f"Server: {server}")
        print(f"User: {email}")
        show_notification("Daemon started", subtitle=email)
    else:
        print("ERROR: Failed to start daemon", file=sys.stderr)
        sys.exit(1)


def cmd_stop():
    """CLI command: bw-stop

    Stop the daemon.
    """
    subprocess.run(["pkill", "-f", "bw-secrets-daemon"], capture_output=True)

    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    print("Daemon stopped")


def cmd_launch():
    """CLI command: bw-launch

    Launcher for launchd. Gets session from Keychain and starts daemon.
    Shows GUI login dialog if not authenticated.
    Includes fail counter to prevent infinite restart loops.
    """
    from .gui import show_alert, show_login_dialog

    def increment_fail_count() -> int:
        try:
            count = int(open(FAIL_COUNT_FILE).read().strip())
        except Exception:
            count = 0
        count += 1
        with open(FAIL_COUNT_FILE, "w") as f:
            f.write(str(count))
        return count

    def handle_failure(message: str):
        print(f"ERROR: {message}", file=sys.stderr)
        fail_count = increment_fail_count()
        print(f"Fail count: {fail_count} / {MAX_FAILURES}", file=sys.stderr)

        if fail_count >= MAX_FAILURES:
            print("Max failures reached. Stopping launchd service.", file=sys.stderr)

            # Stop launchd service
            user = os.environ.get("USER", "")
            label = f"com.{user}.bw-secrets"
            uid = os.getuid()
            subprocess.run(
                ["launchctl", "bootout", f"gui/{uid}/{label}"],
                capture_output=True
            )

            # Show alert
            env = load_env()
            server = env.get("BW_SERVER", "")
            email = env.get("BW_EMAIL", "")
            show_alert(
                f"bw-secrets failed after {MAX_FAILURES} attempts.\n\n"
                f"To restart, run:\n  bw-start\n\n"
                f"Server: {server}\nEmail: {email}"
            )

            # Reset counter
            if os.path.exists(FAIL_COUNT_FILE):
                os.unlink(FAIL_COUNT_FILE)

        sys.exit(1)

    # Load config
    env = load_env()
    server = env.get("BW_SERVER", "https://vault.bitwarden.com")
    email = env.get("BW_EMAIL", "")

    # Configure server
    if server:
        bw_configure_server(server)

    # Check status and try to get session
    status = bw_status()
    session = None
    password = keychain_get("bw-secrets-master")

    # Try with cached credentials first
    if password:
        if status == "unlocked":
            session = keychain_get("bw-secrets-session")
        elif status == "locked":
            session, _ = bw_unlock(password)
        elif status == "unauthenticated":
            session, _ = bw_login(email, password)

    # If no session yet, show GUI login dialog
    if not session:
        error_msg = ""
        max_gui_attempts = 10

        for attempt in range(1, max_gui_attempts + 1):
            result = show_login_dialog(vault=server, email=email, error_msg=error_msg)

            if not result:
                # User cancelled - don't count as failure, just exit
                print("Login cancelled by user", file=sys.stderr)
                sys.exit(0)

            server = result["vault"]
            email = result["email"]
            password = result["password"]

            # Update .env if changed
            if server != env.get("BW_SERVER") or email != env.get("BW_EMAIL"):
                env["BW_SERVER"] = server
                env["BW_EMAIL"] = email
                save_env(env)

            # Configure and authenticate
            bw_configure_server(server)
            status = bw_status()

            if status == "unauthenticated":
                session, auth_error = bw_login(email, password)
            else:
                session, auth_error = bw_unlock(password)

            if session:
                # Save credentials
                keychain_set("bw-secrets-session", session)
                keychain_set("bw-secrets-master", password)
                break

            remaining = max_gui_attempts - attempt
            if remaining > 0:
                error_msg = f"{auth_error}. {remaining} attempt(s) left."
            else:
                error_msg = f"{auth_error}. No attempts left."

    if not session:
        handle_failure("Failed to authenticate after GUI attempts")

    # Verify session is valid
    try:
        result = subprocess.run(
            ["bw", "sync", "--session", session],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            # Session expired, need to re-authenticate
            password = keychain_get("bw-secrets-master")
            if password:
                session = bw_unlock(password)
                if session:
                    keychain_set("bw-secrets-session", session)
                else:
                    handle_failure("Session invalid or expired. Run: bw-start")
            else:
                handle_failure("Session invalid or expired. Run: bw-start")
    except Exception:
        handle_failure("Failed to sync. Run: bw-start")

    # Success - reset fail counter
    if os.path.exists(FAIL_COUNT_FILE):
        os.unlink(FAIL_COUNT_FILE)

    # Start daemon (exec replaces current process)
    os.environ["BW_SESSION"] = session
    project_dir = get_project_dir()
    daemon_path = os.path.join(project_dir, ".venv", "bin", "bw-secrets-daemon")
    os.execv(daemon_path, [daemon_path])
