#!/bin/bash
# TheArchHive - Simplified Claude API Setup Script

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
CLAUDE_CONFIG_DIR="$CONFIG_DIR/claude"
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/config.json"

# Create Claude config directory if it doesn't exist
mkdir -p "$CLAUDE_CONFIG_DIR"

# Display a simple banner
echo "TheArchHive - Claude API Setup"
echo "-----------------------------"
echo ""

# Check for existing config
if [ -f "$CLAUDE_CONFIG_FILE" ]; then
    echo "Claude API is already configured."
    echo ""
    read -p "Do you want to update the API key? (y/n): " update_key
    if [[ "$update_key" != "y" ]]; then
        echo "Keeping existing configuration."
        exit 0
    fi
fi

# Request API key with visible input
echo "To use Claude AI integration, you need an Anthropic API key."
echo "You can get one by signing up at https://console.anthropic.com/"
echo ""
echo "Your API key will be stored locally in: $CLAUDE_CONFIG_FILE"
echo ""

read -p "Please enter your Claude API key: " api_key

if [ -z "$api_key" ]; then
    echo "No API key provided. Setup canceled."
    exit 1
fi

# Show confirmation with partial redaction for security
masked_key="${api_key:0:4}...${api_key: -4}"
echo ""
echo "You entered: $masked_key"
read -p "Is this correct? (y/n): " confirm_key

if [[ "$confirm_key" != "y" ]]; then
    echo "Setup canceled. Please try again."
    exit 1
fi

# Create config file with API key
cat > "$CLAUDE_CONFIG_FILE" << EOF
{
    "api_key": "$api_key",
    "model": "claude-3-5-sonnet-20240620",
    "max_tokens": 4000,
    "temperature": 0.7
}
EOF

# Set secure permissions
chmod 600 "$CLAUDE_CONFIG_FILE"

echo "API key saved successfully."

# Configure Neovim integration
NEOVIM_CONFIG_DIR="$HOME/.config/nvim/lua/claude"
mkdir -p "$NEOVIM_CONFIG_DIR"

# Create or update the Neovim config to use the API config
cat > "$NEOVIM_CONFIG_DIR/config.lua" << EOF
-- Claude configuration for Neovim
local M = {}

M.config_path = "$CLAUDE_CONFIG_FILE"
M.api_configured = true

return M
EOF

echo ""
echo "Claude integration setup complete!"
echo "You can now use Claude in Neovim."
echo "Use <Space>cc to open Claude, and <Space>ca to ask questions."
