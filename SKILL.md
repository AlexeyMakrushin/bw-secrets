# bw-secrets — Bitwarden Secrets Manager

Daemon for secure access to Bitwarden secrets. Allows working with AI assistants without exposing passwords — AI sees only variable names, never actual values.

## When to Use This Skill

- User needs to set up secrets/credentials for a project
- User asks about environment variables or API keys
- User mentions Bitwarden, `.envrc`, or secrets management
- User wants to configure a new project with secure credentials

## Prerequisites

bw-secrets must be installed on the system. Check with:

```bash
bw-list | head -3
```

If not installed, guide user to run:

```bash
git clone https://github.com/AlexeyMakrushin/bw-secrets.git ~/.secrets
cd ~/.secrets && ./setup.sh
```

Setup will automatically:
1. Install Homebrew (if missing)
2. Install dependencies: bitwarden-cli, direnv, uv
3. Ask for Bitwarden server URL (default: vault.bitwarden.com)
4. Configure shell (.zshrc): direnv hook, aliases, PATH
5. Login and unlock Bitwarden vault
6. Install launchd service for auto-start on login
7. Offer to install this skill for detected AI assistants

## CLI Commands (Safe to Run)

| Command | Description |
|---------|-------------|
| `bw-start` | Start daemon or reload cache |
| `bw-stop` | Stop daemon |
| `bw-status` | Show daemon status |
| `bw-list` | List all vault entries |
| `bw-fields <item>` | Show all fields for an entry |
| `bw-get <item> [field]` | Get secret value (default: password) |
| `bw-add <item> field=value` | Create new Bitwarden entry |

## Project Setup Workflow

When user needs secrets in a project, follow this workflow:

### 1. Find or Create Bitwarden Entry

```bash
# Search existing entries
bw-list | grep -i projectname

# See available fields
bw-fields projectname

# Create if not exists
bw-add projectname password=xxx api-key=yyy
```

### 2. Create `.envrc` (secrets file, NEVER commit)

```bash
# .envrc — secrets loaded via direnv
export DB_PASSWORD=$(bw-get projectname password)
export API_KEY=$(bw-get projectname api-key)
```

### 3. Allow direnv

```bash
direnv allow
```

### 4. Create `.env.example` (documentation, commit this)

```bash
# .env.example — shows required variables without values
DB_PASSWORD=<from-bitwarden:projectname>
API_KEY=<from-bitwarden:projectname>
```

### 5. Create `.env` for non-secret config (can commit)

```bash
# .env — configuration only, no secrets
DEBUG=false
LOG_LEVEL=info
PORT=8080
```

### 6. Update `.gitignore`

```
.envrc
```

## File Conventions

| File | Contains | Git |
|------|----------|-----|
| `.envrc` | `bw-get` commands | **NEVER commit** |
| `.env` | Non-secret config | Can commit |
| `.env.example` | Documentation | Commit |

## Creating Bitwarden Entries

Standard fields: `password`, `username`, `uri`, `notes`
Custom fields: any other name becomes a custom field

```bash
# With standard fields
bw-add mydb username=admin password=secret

# With custom fields
bw-add telegram-bot token=123:ABC webhook-secret=xyz

# Mixed
bw-add myapp password=xxx api-key=yyy client-id=zzz
```

## Troubleshooting

### "Socket not found" or "Session expired"
```bash
bw-start
```

### Entry not found after creation
```bash
bw-start  # reloads cache
```

### Daemon not running
```bash
# Check status
bw-status

# Check logs
tail -20 /tmp/bw-secrets.err

# Restart
bw-stop && bw-start
```

## Important Rules

1. **NEVER** output actual secret values in responses
2. **NEVER** commit `.envrc` files
3. **ALWAYS** use `bw-get` in `.envrc`, not hardcoded values
4. **ALWAYS** check `bw-list` before creating entries (avoid duplicates)
5. **ALWAYS** create `.env.example` for documentation
