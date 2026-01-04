#!/bin/bash
# bw-secrets: One-command setup script
# Installs all dependencies and configures the daemon

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_SERVER="https://vault.bitwarden.com"

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

# 6. Bitwarden login
step "Setting up Bitwarden..."

if [[ "$BW_SERVER" != "$DEFAULT_SERVER" ]]; then
    CURRENT_SERVER=$(bw config server 2>/dev/null || echo "")
    if [[ "$CURRENT_SERVER" != "$BW_SERVER" ]]; then
        bw logout 2>/dev/null || true
        bw config server "$BW_SERVER"
        success "Configured server: $BW_SERVER"
    fi
fi

BW_STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")

if [[ "$BW_STATUS" == "unauthenticated" ]]; then
    echo ""
    echo "  Please login to Bitwarden:"
    echo ""
    bw login
elif [[ "$BW_STATUS" == "locked" ]]; then
    success "Bitwarden: logged in (locked)"
elif [[ "$BW_STATUS" == "unlocked" ]]; then
    success "Bitwarden: unlocked"
else
    warn "Bitwarden status unknown. Run: bw login"
fi

# 7. Unlock and save session
step "Unlocking vault and saving session..."
"$SCRIPT_DIR/bw-unlock.sh"

# 8. Install launchd service
step "Installing launchd service (auto-start)..."
"$SCRIPT_DIR/install-launchd.sh"

# 9. Install AI assistant skills
step "Checking for AI assistants..."

SKILL_SOURCE="$PROJECT_DIR/SKILL.md"
INSTALLED_SKILLS=()

# Define AI assistants and their skill directories
declare -A AI_ASSISTANTS=(
    ["Claude Code"]="$HOME/.claude/skills/bw-secrets"
    ["Cursor"]="$HOME/.cursor/skills/bw-secrets"
    ["Windsurf"]="$HOME/.windsurf/skills/bw-secrets"
    ["Continue"]="$HOME/.continue/skills/bw-secrets"
    ["Cody"]="$HOME/.cody/skills/bw-secrets"
    ["Aider"]="$HOME/.aider/skills/bw-secrets"
)

# Check which AI assistants are installed
DETECTED_AI=()
for ai_name in "${!AI_ASSISTANTS[@]}"; do
    parent_dir=$(dirname "${AI_ASSISTANTS[$ai_name]}")
    parent_dir=$(dirname "$parent_dir")  # Go up one more level
    if [[ -d "$parent_dir" ]]; then
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
            skill_dir="${AI_ASSISTANTS[$ai_name]}"
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
    echo "  To install manually: mkdir -p ~/.claude/skills/bw-secrets && cp ~/.secrets/SKILL.md ~/.claude/skills/bw-secrets/"
fi

# Done
echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Setup complete!                    ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Quick test:"
echo "  bw-list | head -5"
echo ""
if [[ ${#INSTALLED_SKILLS[@]} -gt 0 ]]; then
    echo "Skills installed for: ${INSTALLED_SKILLS[*]}"
    echo ""
fi
echo "Use in projects - see README.md"
