SOCKET_PATH = "/tmp/bw-secrets.sock"
VERSION = "0.2.0"

# Export main API
from .client import get_secret, load_secrets

__all__ = ["get_secret", "load_secrets", "SOCKET_PATH", "VERSION"]
