#!/bin/bash
# Сохранить BW_SESSION в macOS Keychain

if [ -z "${BW_SESSION}" ]; then
    echo "ERROR: BW_SESSION not set"
    echo "First run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Сохранить в Keychain
security add-generic-password \
    -a "${USER}" \
    -s "bw-secrets-session" \
    -w "${BW_SESSION}" \
    -U

echo "BW_SESSION saved to Keychain"
echo "Service: bw-secrets-session"
echo "Account: ${USER}"
