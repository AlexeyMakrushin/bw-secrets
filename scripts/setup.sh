#!/bin/bash
# bw-secrets: One-command setup script
# Installs all dependencies and configures the daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_SERVER="https://vault.bitwarden.com"
LAUNCHD_LABEL="com.${USER}.bw-secrets"
PLIST_NAME="${LAUNCHD_LABEL}.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo "╔════════════════════════════════════════╗"
echo "║     bw-secrets setup                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

success() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
step() { echo -e "\n${YELLOW}→${NC} $1"; }

# Check OS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "This script is for macOS only"
    exit 1
fi

# 1. Check Homebrew
step "Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    warn "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH for Apple Silicon
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
fi
success "Homebrew OK"

# 2. Install dependencies
step "Installing dependencies..."
DEPS=(bitwarden-cli direnv uv)
for dep in "${DEPS[@]}"; do
    if ! brew list "$dep" &> /dev/null; then
        echo "  Installing $dep..."
        brew install "$dep"
    fi
done
success "Dependencies installed: ${DEPS[*]}"

# 3. Setup Python environment
step "Setting up Python environment..."
cd "$PROJECT_DIR"
if [[ ! -d .venv ]]; then
    uv sync
fi
success "Python venv ready"

# 4. Configure Bitwarden server
step "Configuring Bitwarden server..."
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo ""
    echo "  Enter your Bitwarden server URL"
    echo "  Press Enter for default: $DEFAULT_SERVER"
    echo ""
    read -p "  Server URL: " BW_SERVER_INPUT

    BW_SERVER="${BW_SERVER_INPUT:-$DEFAULT_SERVER}"

    # Create .env with server
    cat > "$PROJECT_DIR/.env" << EOF
# Bitwarden server URL (self-hosted Vaultwarden or official)
BW_SERVER=$BW_SERVER

# Bitwarden API Key (optional - for non-interactive login)
# Get from: Web Vault → Account Settings → Security → Keys → View API Key
BW_CLIENT_ID=
BW_CLIENT_SECRET=

# Master password (optional - for fully automated unlock)
# WARNING: Store securely, consider using Keychain instead
BW_PASSWORD=
EOF
    success "Created .env with server: $BW_SERVER"
else
    BW_SERVER=$(grep -E "^BW_SERVER=" "$PROJECT_DIR/.env" | cut -d'=' -f2 || echo "$DEFAULT_SERVER")
    success ".env already exists (server: $BW_SERVER)"
fi

# 5. Setup shell (zshrc)
step "Configuring shell..."
ZSHRC="$HOME/.zshrc"
CHANGED=false

touch "$ZSHRC"

# Add direnv hook if missing
if ! grep -q 'eval "$(direnv hook zsh)"' "$ZSHRC" 2>/dev/null; then
    echo '' >> "$ZSHRC"
    echo '# direnv hook (for bw-secrets)' >> "$ZSHRC"
    echo 'eval "$(direnv hook zsh)"' >> "$ZSHRC"
    success "Added direnv hook to .zshrc"
    CHANGED=true
else
    success "direnv hook already in .zshrc"
fi

# Add aliases if missing
if ! grep -q 'alias bw-unlock' "$ZSHRC" 2>/dev/null; then
    echo '' >> "$ZSHRC"
    echo '# bw-secrets aliases' >> "$ZSHRC"
    echo 'alias bw-unlock="~/.secrets/scripts/bw-unlock.sh"' >> "$ZSHRC"
    echo 'alias bw-stop="pkill -f bw-secrets-daemon"' >> "$ZSHRC"
    success "Added bw-secrets aliases to .zshrc"
    CHANGED=true
else
    success "Aliases already in .zshrc"
fi

# Add CLI to PATH if missing
if ! grep -q '.secrets/.venv/bin' "$ZSHRC" 2>/dev/null; then
    echo 'export PATH="$HOME/.secrets/.venv/bin:$PATH"' >> "$ZSHRC"
    success "Added bw-secrets CLI to PATH"
    CHANGED=true
fi

if $CHANGED; then
    warn "Shell config changed. Will apply after restart or: source ~/.zshrc"
fi

export PATH="$PROJECT_DIR/.venv/bin:$PATH"

# 6. Bitwarden login and unlock
step "Setting up Bitwarden..."

# Configure server if not default
if [[ "$BW_SERVER" != "$DEFAULT_SERVER" ]]; then
    CURRENT_SERVER=$(bw config server 2>/dev/null || echo "")
    if [[ "$CURRENT_SERVER" != "$BW_SERVER" ]]; then
        bw logout 2>/dev/null || true
        bw config server "$BW_SERVER"
        success "Configured server: $BW_SERVER"
    fi
fi

BW_STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")

# Login and unlock
if [[ "$BW_STATUS" == "unauthenticated" ]]; then
    echo ""
    echo "  Please login to Bitwarden:"
    echo ""
    read -p "  Email: " BW_EMAIL
    read -s -p "  Master password: " BW_PASS
    echo ""

    # Login and get session in one step
    BW_SESSION=$(echo "$BW_PASS" | bw login "$BW_EMAIL" --raw 2>/dev/null)

    # Clear password from memory
    unset BW_PASS

    if [[ -z "$BW_SESSION" ]]; then
        error "Failed to login. Check email/password."
        exit 1
    fi
    success "Logged in"
elif [[ "$BW_STATUS" == "locked" ]]; then
    echo ""
    read -s -p "  Master password: " BW_PASS
    echo ""

    BW_SESSION=$(echo "$BW_PASS" | bw unlock --passwordenv BW_PASS --raw 2>/dev/null)

    # Alternative method if above fails
    if [[ -z "$BW_SESSION" ]]; then
        export BW_PASS
        BW_SESSION=$(bw unlock --passwordenv BW_PASS --raw 2>/dev/null)
    fi

    unset BW_PASS

    if [[ -z "$BW_SESSION" ]]; then
        error "Failed to unlock vault"
        exit 1
    fi
    success "Vault unlocked"
else
    success "Bitwarden ready"
    BW_SESSION=$(bw unlock --raw 2>/dev/null || echo "")
fi

# Save session to Keychain
if [[ -n "$BW_SESSION" ]]; then
    security add-generic-password \
        -a "${USER}" \
        -s "bw-secrets-session" \
        -w "${BW_SESSION}" \
        -U 2>/dev/null || security add-generic-password \
        -a "${USER}" \
        -s "bw-secrets-session" \
        -w "${BW_SESSION}"
    success "Session saved to Keychain"
fi

# 7. Ask about auto-start daemon
step "Daemon auto-start configuration..."
echo ""
echo "  Start bw-secrets daemon automatically on login?"
echo "  (Recommended for seamless experience)"
echo ""
read -p "  Enable auto-start? [Y/n]: " ENABLE_AUTOSTART
ENABLE_AUTOSTART="${ENABLE_AUTOSTART:-Y}"

if [[ "$ENABLE_AUTOSTART" =~ ^[Yy]$ ]] || [[ -z "$ENABLE_AUTOSTART" ]]; then
    # Create LaunchAgents directory if needed
    mkdir -p "$HOME/Library/LaunchAgents"

    # Stop existing agent if running
    if launchctl list 2>/dev/null | grep -q "$LAUNCHD_LABEL"; then
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
    fi

    # Create plist
    cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PROJECT_DIR/scripts/bw-launch</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/bw-secrets.out</string>

    <key>StandardErrorPath</key>
    <string>/tmp/bw-secrets.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

    # Load agent
    launchctl load "$PLIST_DEST"
    success "Daemon auto-start enabled"

    # Wait and check
    sleep 2
    if [[ -S /tmp/bw-secrets.sock ]]; then
        success "Daemon running (socket: /tmp/bw-secrets.sock)"
    else
        warn "Daemon may need a moment to start. Check: tail -20 /tmp/bw-secrets.err"
    fi
else
    warn "Auto-start disabled. Start manually with: bw-unlock"
fi

# 8. Install AI assistant skills
step "Checking for AI assistants..."

SKILL_SOURCE="$PROJECT_DIR/SKILL.md"
INSTALLED_SKILLS=()

# Define AI assistants and their config directories
declare -A AI_DIRS=(
    ["Claude Code"]="$HOME/.claude"
    ["Cursor"]="$HOME/.cursor"
    ["Windsurf"]="$HOME/.windsurf"
    ["Continue"]="$HOME/.continue"
    ["Cody"]="$HOME/.cody"
    ["Aider"]="$HOME/.aider"
)

# Check which AI assistants are installed
DETECTED_AI=()
for ai_name in "${!AI_DIRS[@]}"; do
    if [[ -d "${AI_DIRS[$ai_name]}" ]]; then
        DETECTED_AI+=("$ai_name")
    fi
done

if [[ ${#DETECTED_AI[@]} -gt 0 ]]; then
    echo ""
    echo "  Detected AI assistants: ${DETECTED_AI[*]}"
    echo ""
    echo "  Install bw-secrets skill for these assistants?"
    echo "  This teaches AI how to work with your secrets securely."
    echo ""
    read -p "  Install skills? [Y/n]: " INSTALL_SKILLS
    INSTALL_SKILLS="${INSTALL_SKILLS:-Y}"

    if [[ "$INSTALL_SKILLS" =~ ^[Yy]$ ]] || [[ -z "$INSTALL_SKILLS" ]]; then
        for ai_name in "${DETECTED_AI[@]}"; do
            skill_dir="${AI_DIRS[$ai_name]}/skills/bw-secrets"
            mkdir -p "$skill_dir"
            cp "$SKILL_SOURCE" "$skill_dir/"
            INSTALLED_SKILLS+=("$ai_name")
            success "Installed skill for $ai_name"
        done
    else
        warn "Skipped skill installation"
    fi
else
    warn "No AI assistants detected"
    echo "  To install manually later:"
    echo "  mkdir -p ~/.claude/skills/bw-secrets && cp ~/.secrets/SKILL.md ~/.claude/skills/bw-secrets/"
fi

# Done
echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Setup complete!                    ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Quick test:"
echo "  source ~/.zshrc"
echo "  bw-list | head -5"
echo ""
if [[ ${#INSTALLED_SKILLS[@]} -gt 0 ]]; then
    echo "Skills installed for: ${INSTALLED_SKILLS[*]}"
    echo ""
fi
echo "Use in projects — see README.md"
