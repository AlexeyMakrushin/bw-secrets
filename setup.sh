#!/bin/bash
# bw-secrets: One-command setup script
# Installs all dependencies and configures the daemon

set -e

# Script is in project root
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

# Read existing server from .env if present
BW_SERVER=""
if [[ -f "$PROJECT_DIR/.env" ]]; then
    BW_SERVER=$(grep -E "^BW_SERVER=" "$PROJECT_DIR/.env" | cut -d'=' -f2)
fi

# Ask for server if not configured
if [[ -z "$BW_SERVER" ]]; then
    echo ""
    echo "  Enter your Bitwarden server URL"
    echo "  Press Enter for default: $DEFAULT_SERVER"
    echo ""
    read -p "  Server URL: " BW_SERVER_INPUT
    BW_SERVER="${BW_SERVER_INPUT:-$DEFAULT_SERVER}"
fi

# Add https:// if missing
if [[ -n "$BW_SERVER" ]] && [[ ! "$BW_SERVER" =~ ^https?:// ]]; then
    BW_SERVER="https://$BW_SERVER"
fi
success "Server: $BW_SERVER"

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

# Add CLI to PATH if missing (no aliases needed - commands are entry points)
if ! grep -q '.secrets/.venv/bin' "$ZSHRC" 2>/dev/null; then
    echo 'export PATH="$HOME/.secrets/.venv/bin:$PATH"' >> "$ZSHRC"
    success "Added bw-secrets CLI to PATH"
    CHANGED=true
fi

if $CHANGED; then
    warn "Shell config changed. Will apply after restart or: source ~/.zshrc"
fi

export PATH="$PROJECT_DIR/.venv/bin:$PATH"

# 6. Save server config to .env (email will be saved by bw-start GUI)
step "Saving configuration..."

# Create minimal .env with server
cat > "$PROJECT_DIR/.env" << EOF
# bw-secrets configuration
BW_SERVER=$BW_SERVER
EOF
success "Server saved to .env"

# 7. Bitwarden login via GUI
step "Setting up Bitwarden (GUI login)..."

# Configure server if not default
if [[ "$BW_SERVER" != "$DEFAULT_SERVER" ]]; then
    BW_STATUS=$(bw status 2>/dev/null | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    if [[ "$BW_STATUS" == "unauthenticated" ]]; then
        bw config server "$BW_SERVER"
        success "Configured server: $BW_SERVER"
    fi
fi

# Use bw-start which shows GUI dialog for login
echo ""
echo "  A login dialog will appear."
echo "  Enter your Bitwarden credentials."
echo ""

if "$PROJECT_DIR/.venv/bin/bw-start"; then
    success "Bitwarden authenticated via GUI"
else
    error "Failed to authenticate. Run: bw-start"
    exit 1
fi

# 8. Ask about auto-start daemon
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
        <string>$PROJECT_DIR/.venv/bin/bw-launch</string>
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
    warn "Auto-start disabled. Start manually with: bw-start"
fi

# 9. Install keyboard shortcut (Automator Service)
step "Keyboard shortcut configuration..."
echo ""
echo "  Global keyboard shortcut to launch bw-start"
echo "  Default: Ctrl+Option+Cmd+B (⌃⌥⌘B)"
echo ""
echo "  Options:"
echo "    1) Use default (⌃⌥⌘B)"
echo "    2) Skip (no shortcut)"
echo ""
read -p "  Choice [1]: " SHORTCUT_CHOICE
SHORTCUT_CHOICE="${SHORTCUT_CHOICE:-1}"

if [[ "$SHORTCUT_CHOICE" == "2" ]]; then
    warn "Keyboard shortcut skipped. You can add it manually later in System Settings."
else
    WORKFLOW_DIR="$HOME/Library/Services/bw-start.workflow"
    mkdir -p "$WORKFLOW_DIR/Contents"

# Create Automator workflow for Quick Action
cat > "$WORKFLOW_DIR/Contents/document.wflow" << 'WFLOW'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>523</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMAccepts</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Optional</key>
					<true/>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>AMApplication</key>
				<array>
					<string>Automator</string>
				</array>
				<key>AMCategory</key>
				<string>AMCategoryUtilities</string>
				<key>AMIconName</key>
				<string>Automator</string>
				<key>AMName</key>
				<string>Run Shell Script</string>
				<key>AMProvides</key>
				<dict>
					<key>Container</key>
					<string>List</string>
					<key>Types</key>
					<array>
						<string>com.apple.cocoa.string</string>
					</array>
				</dict>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>__PROJECT_DIR__/.venv/bin/bw-start</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>1</integer>
					<key>shell</key>
					<string>/bin/zsh</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>E7A5B8B0-5E5A-4E5C-9B5A-8E5A5E5A5E5A</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
					<string>Run</string>
					<string>Unix</string>
				</array>
				<key>OutputUUID</key>
				<string>F8B6C9C1-6F6B-5F6D-AC6B-9F6B6F6B6F6B</string>
				<key>UUID</key>
				<string>D6A4A7A0-4D4A-3D4B-8A4A-7D4A4D4A4D4A</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>arguments</key>
				<dict>
					<key>0</key>
					<dict>
						<key>default value</key>
						<integer>0</integer>
						<key>name</key>
						<string>inputMethod</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>0</string>
					</dict>
					<key>1</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>source</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>1</string>
					</dict>
					<key>2</key>
					<dict>
						<key>default value</key>
						<false/>
						<key>name</key>
						<string>CheckedForUserDefaultShell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>2</string>
					</dict>
					<key>3</key>
					<dict>
						<key>default value</key>
						<string></string>
						<key>name</key>
						<string>COMMAND_STRING</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>3</string>
					</dict>
					<key>4</key>
					<dict>
						<key>default value</key>
						<string>/bin/zsh</string>
						<key>name</key>
						<string>shell</string>
						<key>required</key>
						<string>0</string>
						<key>type</key>
						<string>0</string>
						<key>uuid</key>
						<string>4</string>
					</dict>
				</dict>
				<key>isViewVisible</key>
				<integer>1</integer>
				<key>location</key>
				<string>309.500000:253.000000</string>
				<key>nibPath</key>
				<string>/System/Library/Automator/Run Shell Script.action/Contents/Resources/Base.lproj/main.nib</string>
			</dict>
			<key>isViewVisible</key>
			<integer>1</integer>
		</dict>
	</array>
	<key>connectors</key>
	<dict/>
	<key>workflowMetaData</key>
	<dict>
		<key>applicationBundleIDsByPath</key>
		<dict/>
		<key>applicationPaths</key>
		<array/>
		<key>inputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>outputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>presentationMode</key>
		<integer>11</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>systemImageName</key>
		<string>NSTouchBarQuickLook</string>
		<key>useAutomaticInputType</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
WFLOW

# Create Info.plist
cat > "$WORKFLOW_DIR/Contents/Info.plist" << 'INFOPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>bw-start</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSRequiredContext</key>
			<dict/>
			<key>NSSendTypes</key>
			<array/>
			<key>NSReturnTypes</key>
			<array/>
		</dict>
	</array>
</dict>
</plist>
INFOPLIST

    # Replace placeholder with actual path
    sed -i '' "s|__PROJECT_DIR__|$PROJECT_DIR|g" "$WORKFLOW_DIR/Contents/document.wflow"

    success "Quick Action 'bw-start' installed"

    # Assign keyboard shortcut: Ctrl+Opt+Cmd+B
    defaults write pbs NSServicesStatus -dict-add \
        '"(null) - bw-start - runWorkflowAsService"' \
        '{ "enabled_context_menu" = 1; "enabled_services_menu" = 1; "key_equivalent" = "@^~b"; }'

    # Restart pasteboard server to apply
    killall pbs 2>/dev/null || true

    success "Keyboard shortcut: Ctrl+Opt+Cmd+B"
fi

# 10. Install AI assistant skills
step "Checking for AI assistants..."

SKILL_SOURCE="$PROJECT_DIR/SKILL.md"
DETECTED=""
INSTALLED=""

# Check for AI assistants and collect detected ones
# Format: name:directory
check_ai() {
    local name="$1"
    local dir="$2"
    if [[ -d "$dir" ]]; then
        DETECTED="$DETECTED $name:$dir"
    fi
}

# Anthropic
check_ai "Claude" "$HOME/.claude"
# OpenAI
check_ai "Codex" "$HOME/.codex"
check_ai "Copilot" "$HOME/.config/github-copilot"
# Google
check_ai "Gemini" "$HOME/.gemini"
# Chinese AI
check_ai "DeepSeek" "$HOME/.deepseek"
check_ai "Qwen" "$HOME/.qwen"
check_ai "GLM" "$HOME/.glm"
check_ai "ChatGLM" "$HOME/.chatglm"
check_ai "Baichuan" "$HOME/.baichuan"
check_ai "Yi" "$HOME/.yi"
# IDE-integrated
check_ai "Cursor" "$HOME/.cursor"
check_ai "Windsurf" "$HOME/.windsurf"
check_ai "Codeium" "$HOME/.codeium"
check_ai "Zed" "$HOME/.zed"
# Extensions/Plugins
check_ai "Continue" "$HOME/.continue"
check_ai "Cody" "$HOME/.cody"
check_ai "Cline" "$HOME/.cline"
check_ai "Roo" "$HOME/.roo"
check_ai "Aider" "$HOME/.aider"
# Other
check_ai "Replit" "$HOME/.replit"
check_ai "Supermaven" "$HOME/.supermaven"
check_ai "Pieces" "$HOME/.pieces"
check_ai "Phind" "$HOME/.phind"
check_ai "Tabnine" "$HOME/.tabnine"
check_ai "AmazonQ" "$HOME/.amazon-q"
check_ai "Blackbox" "$HOME/.blackbox"
check_ai "CodeGPT" "$HOME/.codegpt"
check_ai "Bito" "$HOME/.bito"

if [[ -n "$DETECTED" ]]; then
    # Extract just names for display
    NAMES=$(echo "$DETECTED" | tr ' ' '\n' | cut -d: -f1 | tr '\n' ' ')
    echo ""
    echo "  Detected AI assistants: $NAMES"
    echo ""
    echo "  Install bw-secrets skill for these assistants?"
    echo "  This teaches AI how to work with your secrets securely."
    echo ""
    read -p "  Install skills? [Y/n]: " INSTALL_SKILLS
    INSTALL_SKILLS="${INSTALL_SKILLS:-Y}"

    if [[ "$INSTALL_SKILLS" =~ ^[Yy]$ ]] || [[ -z "$INSTALL_SKILLS" ]]; then
        for item in $DETECTED; do
            ai_name="${item%%:*}"
            ai_dir="${item#*:}"
            skill_dir="$ai_dir/skills/bw-secrets"
            mkdir -p "$skill_dir"
            # Use symlink instead of copy for auto-updates
            ln -sf "$SKILL_SOURCE" "$skill_dir/SKILL.md"
            INSTALLED="$INSTALLED $ai_name"
            success "Installed skill for $ai_name (symlink)"
        done
    else
        warn "Skipped skill installation"
    fi
else
    warn "No AI assistants detected"
    echo "  To install manually later:"
    echo "  mkdir -p ~/.claude/skills/bw-secrets && cp ~/.secrets/SKILL.md ~/.claude/skills/bw-secrets/"
fi

# 11. Ensure daemon is running
step "Starting daemon..."
sleep 1
if [[ ! -S /tmp/bw-secrets.sock ]]; then
    # Try to start via launchd first
    if launchctl list 2>/dev/null | grep -q "$LAUNCHD_LABEL"; then
        launchctl kickstart -k "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
        sleep 2
    fi

    # If still not running, start manually
    if [[ ! -S /tmp/bw-secrets.sock ]]; then
        export BW_SESSION
        "$PROJECT_DIR/.venv/bin/bw-secrets-daemon" &
        sleep 2
    fi
fi

if [[ -S /tmp/bw-secrets.sock ]]; then
    success "Daemon running"
else
    warn "Daemon not started. Run: bw-start"
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
if [[ -n "$INSTALLED" ]]; then
    echo "Skills installed for:$INSTALLED"
    echo ""
fi
echo "Use in projects — see README.md"
