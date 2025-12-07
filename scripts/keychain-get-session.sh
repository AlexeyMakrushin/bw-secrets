#!/bin/bash
# Получить BW_SESSION из macOS Keychain

security find-generic-password \
    -a "${USER}" \
    -s "bw-secrets-session" \
    -w 2>/dev/null
