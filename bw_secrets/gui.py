"""GUI dialogs for bw-secrets using tkinter."""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Optional


def show_login_dialog(vault: str = "", email: str = "", error_msg: str = "") -> Optional[dict]:
    """Show login dialog with all fields in one window.

    Uses system Python's tkinter for proper GUI support.
    Returns dict with vault, email, password or None if cancelled.
    """
    # Create a temporary Python script for system Python
    script = '''
import tkinter as tk
from tkinter import ttk
import json
import sys

class LoginDialog:
    def __init__(self, vault, email, error_msg):
        self.result = None

        # Window setup
        self.root = tk.Tk()
        self.root.title("bw-secrets")
        self.root.geometry("420x300")
        self.root.resizable(False, False)

        # Center on screen
        self.root.update_idletasks()
        x = (self.root.winfo_screenwidth() - 420) // 2
        y = (self.root.winfo_screenheight() - 300) // 2
        self.root.geometry(f"420x300+{x}+{y}")

        # Bring to front
        self.root.lift()
        self.root.attributes("-topmost", True)
        self.root.after(100, lambda: self.root.attributes("-topmost", False))
        self.root.focus_force()

        # Use native macOS theme
        style = ttk.Style()
        style.theme_use("aqua")
        style.configure("Error.TLabel", foreground="red")
        style.configure("Info.TLabel", foreground="#666666")

        # Main frame
        main = ttk.Frame(self.root, padding=20)
        main.pack(fill="both", expand=True)

        # Title
        title = ttk.Label(main, text="Bitwarden Login", font=("SF Pro Display", 16, "bold"))
        title.pack(pady=(0, 10))

        # Status message - always shown
        if error_msg:
            msg_label = ttk.Label(main, text=error_msg, style="Error.TLabel")
        else:
            msg_label = ttk.Label(main, text="Enter your master password", style="Info.TLabel")
        msg_label.pack(pady=(0, 10))

        # Server URL
        ttk.Label(main, text="Server URL").pack(anchor="w")
        self.vault_var = tk.StringVar(value=vault)
        self.vault_entry = ttk.Entry(main, textvariable=self.vault_var, width=45)
        self.vault_entry.pack(fill="x", pady=(0, 10))

        # Email
        ttk.Label(main, text="Email").pack(anchor="w")
        self.email_var = tk.StringVar(value=email)
        self.email_entry = ttk.Entry(main, textvariable=self.email_var, width=45)
        self.email_entry.pack(fill="x", pady=(0, 10))

        # Password with toggle button
        ttk.Label(main, text="Password").pack(anchor="w")
        pass_frame = ttk.Frame(main)
        pass_frame.pack(fill="x", pady=(0, 10))

        self.pass_var = tk.StringVar()
        self.pass_entry = ttk.Entry(pass_frame, textvariable=self.pass_var, width=40, show="*")
        self.pass_entry.pack(side="left", fill="x", expand=True)

        self.show_pass = False
        self.toggle_btn = ttk.Button(pass_frame, text="Show", width=5, command=self.toggle_password)
        self.toggle_btn.pack(side="right", padx=(5, 0))

        # Buttons
        btn_frame = ttk.Frame(main)
        btn_frame.pack(fill="x", pady=(10, 0))

        cancel_btn = ttk.Button(btn_frame, text="Cancel", command=self.cancel)
        cancel_btn.pack(side="left")

        login_btn = ttk.Button(btn_frame, text="Login", command=self.login)
        login_btn.pack(side="right")

        # Focus
        if vault and email:
            self.pass_entry.focus()
        elif vault:
            self.email_entry.focus()
        else:
            self.vault_entry.focus()

        # Bindings
        self.root.bind("<Return>", lambda e: self.login())
        self.root.bind("<Escape>", lambda e: self.cancel())
        self.root.protocol("WM_DELETE_WINDOW", self.cancel)

    def toggle_password(self):
        self.show_pass = not self.show_pass
        if self.show_pass:
            self.pass_entry.config(show="")
            self.toggle_btn.config(text="Hide")
        else:
            self.pass_entry.config(show="*")
            self.toggle_btn.config(text="Show")

    def login(self):
        vault = self.vault_var.get().strip()
        email = self.email_var.get().strip()
        password = self.pass_var.get()

        if not vault or not email or not password:
            return

        self.result = {"vault": vault, "email": email, "password": password}
        self.root.destroy()

    def cancel(self):
        self.result = None
        self.root.destroy()

    def run(self):
        self.root.mainloop()
        return self.result

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--vault", default="")
    parser.add_argument("--email", default="")
    parser.add_argument("--error", default="")
    args = parser.parse_args()

    dialog = LoginDialog(args.vault, args.email, args.error)
    result = dialog.run()

    if result:
        print(json.dumps(result))
        sys.exit(0)
    else:
        sys.exit(1)
'''

    try:
        # Run with Homebrew Python (has tkinter)
        result = subprocess.run(
            ["/opt/homebrew/bin/python3", "-c", script,
             "--vault", vault, "--email", email, "--error", error_msg],
            capture_output=True, text=True, timeout=300
        )

        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout.strip())
        return None

    except Exception:
        return None


def show_alert(message: str, title: str = "bw-secrets"):
    """Show an alert dialog."""
    subprocess.run(
        ["osascript", "-e", f'display alert "{title}" message "{message}"'],
        capture_output=True
    )


def show_notification(message: str, title: str = "bw-secrets", subtitle: str = ""):
    """Show a macOS notification."""
    script = f'display notification "{message}" with title "{title}"'
    if subtitle:
        script = f'display notification "{message}" with title "{title}" subtitle "{subtitle}"'
    subprocess.run(["osascript", "-e", script], capture_output=True)


def cmd_login_gui():
    """CLI entry point for testing the GUI."""
    import argparse

    parser = argparse.ArgumentParser(description="Show login dialog")
    parser.add_argument("--vault", default="https://vault.bitwarden.com")
    parser.add_argument("--email", default="")
    parser.add_argument("--error", default="")
    args = parser.parse_args()

    result = show_login_dialog(args.vault, args.email, args.error)

    if result:
        # Don't print password
        print(f"Server: {result['vault']}")
        print(f"Email: {result['email']}")
        print("Password: ***")
    else:
        print("Cancelled")
        sys.exit(1)
