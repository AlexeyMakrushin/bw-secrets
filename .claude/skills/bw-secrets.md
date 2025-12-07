# bw-secrets skill

Use this skill to safely work with secrets from Bitwarden vault via bw-secrets daemon.

## When to use this skill

- User asks to get a secret/password for a service
- User wants to generate environment variables from Bitwarden
- User needs to inject secrets into Docker, scripts, or applications
- User asks to set up credentials for a service

## Prerequisites

The bw-secrets daemon must be running. Check with:
```bash
ls -la /tmp/bw-secrets.sock
```

If not running, guide user to start it:
```bash
bw-start  # or: cd ~/.secrets && ./scripts/start-daemon.sh &
```

## Available commands

### 1. List all items
```bash
cd ~/.secrets && .venv/bin/bw-list
```
Shows all available Bitwarden entries (names only, no secrets).

### 2. Get a specific secret
```bash
cd ~/.secrets && .venv/bin/bw-get <item> <field>
```

Examples:
- `bw-get google password` - get password field
- `bw-get openai api-key` - get custom field "api-key"
- `bw-get myapp username` - get username field

Default field is "password" if not specified.

### 3. Suggest environment variables
```bash
cd ~/.secrets && .venv/bin/bw-suggest <item>
```

Shows all fields formatted as environment variable assignments.

Example output:
```
GOOGLE_USERNAME=$(bw-get google username)
GOOGLE_PASSWORD=$(bw-get google password)
GOOGLE_API_KEY=$(bw-get google api-key)
```

### 4. Reload vault
```bash
cd ~/.secrets && .venv/bin/bw-reload
```

Reloads vault if user added/changed items in Bitwarden.

## Usage patterns

### For shell scripts
```bash
# Single variable
API_KEY=$(~/.secrets/.venv/bin/bw-get openai api-key)

# Multiple variables at once
eval "$(~/.secrets/.venv/bin/bw-suggest myapp)"
# Now available: $MYAPP_USERNAME, $MYAPP_PASSWORD, etc.
```

### For Docker
```bash
docker run \
  -e OPENAI_API_KEY=$(~/.secrets/.venv/bin/bw-get openai api-key) \
  -e DB_PASSWORD=$(~/.secrets/.venv/bin/bw-get postgres password) \
  myapp
```

### For docker-compose.yml
Add comment instructions for user:
```yaml
environment:
  # Run: OPENAI_API_KEY=$(~/.secrets/.venv/bin/bw-get openai api-key)
  OPENAI_API_KEY: ${OPENAI_API_KEY}
```

### For Python code
```python
from bw_secrets import get_secret

api_key = get_secret("openai", "api-key")
password = get_secret("postgres", "password")
```

## Security rules (CRITICAL)

### NEVER:
1. **Echo or print secret values** - NEVER use echo, print, or any output commands with secret values
2. **Store secrets in files** - DO NOT write secrets to .env, config files, or any persistent storage
3. **Show secrets in responses** - DO NOT include actual secret values in your responses to user
4. **Log secrets** - DO NOT add logging statements that would expose secrets

### ALWAYS:
1. **Use bw-get in subshells** - Always use `$(bw-get ...)` to inject secrets directly
2. **Verify daemon is running** - Check socket exists before using commands
3. **Guide user to use bw-suggest** - Show user the suggested variable names
4. **Use comments in configs** - Show how to inject secrets, but don't actually inject them

## Environment variable naming

bw-secrets automatically converts to UPPER_SNAKE_CASE:
- `my-app` → `MY_APP`
- `api-key` → `API_KEY`
- `google-cloud` → `GOOGLE_CLOUD`

Combined format: `{ITEM}_{FIELD}`
- Item: `google`, Field: `password` → `GOOGLE_PASSWORD`
- Item: `my-app`, Field: `api-key` → `MY_APP_API_KEY`

## Error handling

If command fails:
1. Check if daemon is running: `ls -la /tmp/bw-secrets.sock`
2. If socket missing: `bw-start` or `cd ~/.secrets && ./scripts/start-daemon.sh &`
3. If item not found: use `bw-list` to see available items
4. If field not found: use `bw-suggest <item>` to see available fields

## Example workflows

### Workflow 1: User wants OpenAI credentials
Assistant steps:
1. Check if daemon is running: `ls -la /tmp/bw-secrets.sock`
2. List available items: `cd ~/.secrets && .venv/bin/bw-list | grep -i openai`
3. Show suggested variables: `cd ~/.secrets && .venv/bin/bw-suggest openai`
4. Guide user on usage (DO NOT actually get the secret)

### Workflow 2: User setting up docker-compose
Assistant steps:
1. Identify which secrets are needed (e.g., database, API keys)
2. Use `bw-suggest` to show environment variable format
3. Add comments to docker-compose.yml with bw-get commands
4. Instruct user to export variables before running docker-compose

Example docker-compose.yml:
```yaml
services:
  app:
    environment:
      # Export before starting:
      # export OPENAI_API_KEY=$(~/.secrets/.venv/bin/bw-get openai api-key)
      # export DB_PASSWORD=$(~/.secrets/.venv/bin/bw-get postgres password)
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      DB_PASSWORD: ${DB_PASSWORD}
```

### Workflow 3: User creating shell script
Assistant steps:
1. Write script that uses `$(bw-get ...)` subshells
2. Add error checking for daemon availability
3. DO NOT hardcode any secrets in the script

Example script:
```bash
#!/bin/bash

# Check if bw-secrets daemon is running
if [ ! -S /tmp/bw-secrets.sock ]; then
    echo "ERROR: bw-secrets daemon not running"
    echo "Start it with: bw-start"
    exit 1
fi

# Get secrets (values never stored in script)
API_KEY=$(~/.secrets/.venv/bin/bw-get openai api-key)
DB_PASS=$(~/.secrets/.venv/bin/bw-get postgres password)

# Use secrets
curl -H "Authorization: Bearer $API_KEY" https://api.openai.com/v1/models
```

## Summary

This skill helps safely work with secrets by:
- Using bw-secrets daemon instead of .env files
- Never exposing actual secret values
- Teaching users proper secret injection patterns
- Following security-first principles
