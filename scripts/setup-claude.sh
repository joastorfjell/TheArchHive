#!/bin/bash
# TheArchHive - Simplified Claude API Setup Script

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Define the correct configuration paths
HOME_CONFIG_DIR="$HOME/.config/thearchhive"
HOME_CONFIG_FILE="$HOME_CONFIG_DIR/claude_config.json"

# Create Claude config directory if it doesn't exist
mkdir -p "$HOME_CONFIG_DIR"

# Display a simple banner
echo "TheArchHive - Claude API Setup"
echo "-----------------------------"
echo ""

# Check for existing config
if [ -f "$HOME_CONFIG_FILE" ]; then
    echo "Claude API is already configured at: $HOME_CONFIG_FILE"
    echo ""
    read -p "Do you want to update the API key? (y/n): " update_key
    if [[ "$update_key" != "y" ]]; then
        echo "Keeping existing configuration."
        
        # Update Neovim config to point to the correct location
        update_neovim_config
        
        exit 0
    fi
fi

# Request API key with visible input
echo "To use Claude AI integration, you need an Anthropic API key."
echo "You can get one by signing up at https://console.anthropic.com/"
echo ""
echo "Your API key will be stored locally in: $HOME_CONFIG_FILE"
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

# Create config file with API key in the HOME directory location
cat > "$HOME_CONFIG_FILE" << EOF
{
    "api_key": "$api_key",
    "model": "claude-3-5-sonnet-20240620",
    "max_tokens": 4000,
    "temperature": 0.7
}
EOF

# Set secure permissions
chmod 600 "$HOME_CONFIG_FILE"

echo "API key saved successfully to: $HOME_CONFIG_FILE"

# Configure Neovim integration
NEOVIM_CONFIG_DIR="$HOME/.config/nvim/lua/claude"
mkdir -p "$NEOVIM_CONFIG_DIR"

# Create or update the Neovim config to use the HOME directory config file
cat > "$NEOVIM_CONFIG_DIR/config.lua" << EOF
-- Claude configuration for Neovim
local M = {}

M.config_path = "$HOME_CONFIG_FILE"
M.api_configured = true

return M
EOF

# Check for any old config file in the repository and warn about it
REPO_CONFIG_DIR="$PROJECT_ROOT/config/claude"
REPO_CONFIG_FILE="$REPO_CONFIG_DIR/config.json"
if [ -f "$REPO_CONFIG_FILE" ]; then
    echo ""
    echo "WARNING: Found an old configuration file at: $REPO_CONFIG_FILE"
    echo "This file is no longer used. The new configuration is at: $HOME_CONFIG_FILE"
    read -p "Do you want to remove the old config file? (y/n): " remove_old
    if [[ "$remove_old" == "y" ]]; then
        rm -f "$REPO_CONFIG_FILE"
        echo "Old configuration file removed."
    fi
fi

echo ""
echo "Claude integration setup complete!"
echo "Configuration saved to: $HOME_CONFIG_FILE"
echo "Neovim integration configured to use this location."
echo "You can now use Claude in Neovim."
echo "Use <Space>cc to open Claude, and <Space>ca to ask questions."
