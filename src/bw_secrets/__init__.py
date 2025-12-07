SOCKET_PATH = "/tmp/bw-secrets.sock"
VERSION = "0.1.0"

# Export main API
from .client import get_secret

__all__ = ["get_secret", "SOCKET_PATH", "VERSION"]
