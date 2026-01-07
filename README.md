# bw-secrets

**Use AI coding assistants without ever exposing your passwords.**

bw-secrets lets you work with Claude, Cursor, Copilot, and other AI tools while keeping your credentials secure in Bitwarden. The AI never sees your actual passwords — it only knows the *names* of secrets and retrieves them at runtime.

## Why?

When you use AI assistants to write code, you face a dilemma:
- Share your `.env` file → AI sees your passwords
- Don't share → AI can't help with configuration

**bw-secrets solves this:**
- AI sees: `export DB_PASSWORD=$(bw-get myapp password)`
- AI never sees: the actual password value
- Your app gets: the real password at runtime

No `.env` files with secrets on disk. No passwords in your prompts. No trust required.

## How It Works

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Your Code     │────▶│   .envrc        │────▶│   bw-secrets    │
│   (or AI)       │     │   (references)  │     │   daemon        │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │   Bitwarden     │
                                                │   (encrypted)   │
                                                └─────────────────┘
```

1. **Daemon** loads your Bitwarden vault into memory (once)
2. **direnv** reads `.envrc` when you enter a project directory
3. **bw-get** fetches secrets from the daemon instantly
4. **Your app** receives environment variables with real values
5. **AI** only sees the `.envrc` template — never the values

## Quick Start

```bash
# Clone and run setup
git clone https://github.com/AlexeyMakrushin/bw-secrets.git ~/.secrets
cd ~/.secrets && ./setup.sh
```

The setup will:
1. Install dependencies (bitwarden-cli, direnv, uv)
2. Ask for your Bitwarden server (default: vault.bitwarden.com)
3. Configure your shell
4. Login and unlock your vault
5. Start the daemon (auto-starts on login)

## Using in Projects

### Step 1: Create `.envrc` (secrets)

```bash
# .envrc — loaded by direnv, NEVER commit this file
export DB_PASSWORD=$(bw-get myapp password)
export API_KEY=$(bw-get myapp api-key)
export OPENAI_KEY=$(bw-get openai api-key)
```

### Step 2: Allow direnv

```bash
direnv allow
```

### Step 3: Create `.env.example` (documentation)

```bash
# .env.example — commit this, shows required variables
DB_PASSWORD=<from-bitwarden:myapp>
API_KEY=<from-bitwarden:myapp>
OPENAI_KEY=<from-bitwarden:openai>
```

### Step 4: Create `.env` (non-secret config)

```bash
# .env — safe to commit, no secrets here
DEBUG=false
LOG_LEVEL=info
PORT=8080
```

### Step 5: Add to `.gitignore`

```
.envrc
```

## File Conventions

| File | Contains | Commit? |
|------|----------|---------|
| `.envrc` | `bw-get` commands | **Never** |
| `.env` | Non-secret config | Yes |
| `.env.example` | Documentation | Yes |

## CLI Reference

| Command | Description |
|---------|-------------|
| `bw-start` | Start daemon or reload cache |
| `bw-stop` | Stop daemon |
| `bw-status` | Show daemon status |
| `bw-list` | List all vault entries |
| `bw-fields <item>` | Show fields for an entry |
| `bw-get <item> [field]` | Get secret (default: password) |
| `bw-add <item> key=value` | Create new entry |

### Examples

```bash
# Find entries
bw-list | grep -i postgres

# See available fields
bw-fields myapp

# Get specific field
bw-get myapp api-key

# Create new entry
bw-add telegram-bot token=123:ABC password=secret
```

## Requirements

- macOS (Apple Silicon or Intel)
- [Homebrew](https://brew.sh)
- [Bitwarden](https://bitwarden.com) account (cloud or self-hosted)

Dependencies installed automatically by setup:
- bitwarden-cli
- direnv
- uv (Python package manager)

## For AI Coding Assistants

This repository includes `SKILL.md` — a skill file that teaches AI assistants how to work with bw-secrets securely.

**Automatic installation:** The setup script detects installed AI assistants and offers to install the skill automatically. Supported:
- Claude Code (`~/.claude/skills/bw-secrets/`)
- Cursor (`~/.cursor/skills/bw-secrets/`)
- Windsurf (`~/.windsurf/skills/bw-secrets/`)
- Continue (`~/.continue/skills/bw-secrets/`)
- Cody (`~/.cody/skills/bw-secrets/`)
- Aider (`~/.aider/skills/bw-secrets/`)

**Manual installation:**

```bash
mkdir -p ~/.claude/skills/bw-secrets
cp ~/.secrets/SKILL.md ~/.claude/skills/bw-secrets/
```

## Configuration

Edit `~/.secrets/.env`:

```bash
# Self-hosted Vaultwarden
BW_SERVER=https://vault.example.com

# API key for non-interactive login (optional)
BW_CLIENT_ID=user.xxx
BW_CLIENT_SECRET=xxx
```

## Troubleshooting

### "Socket not found" or "Session expired"
```bash
bw-start
```

### Daemon not starting
```bash
# Check status
bw-status

# Check logs
tail -20 /tmp/bw-secrets.err

# Restart
bw-stop && bw-start
```

## Security

- Secrets stored only in RAM, never on disk
- Unix socket with 600 permissions (owner only)
- Session key stored in macOS Keychain (encrypted)
- AI assistants see only variable names, never values

## Structure

```
~/.secrets/
├── setup.sh              # One-command installation
├── bw_secrets/           # Python package
│   ├── cli.py            # CLI commands
│   ├── daemon.py         # Background service
│   └── gui.py            # Login dialog
├── SKILL.md              # AI assistant skill
└── .env                  # Your server config
```

## License

MIT
