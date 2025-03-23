#!/bin/bash
# TheArchHive - Claude API Setup Script
# This script handles the setup of Claude API integration

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"
CLAUDE_CONFIG_DIR="$CONFIG_DIR/claude"
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/config.json"

# Create Claude config directory if it doesn't exist
mkdir -p "$CLAUDE_CONFIG_DIR"

# ASCII art banner
display_banner() {
    echo -e "\033[0;36m"
    echo "  _____ _           _            _     _   _ _           "
    echo " |_   _| |__   ___ / \   _ __ __| |__ | | | |_|_   _____ "
    echo "   | | | '_ \ / _ \ \ | | '__/ _\` '_ \| |_| | \ \ / / _ \\"
    echo "   | | | | | |  __/ _ \| | | (_| | | | |  _  | |\ V /  __/"
    echo "   |_| |_| |_|\___\_/ \_\_|  \__,_|_| |_|_| |_|_| \_/ \___|"
    echo ""
    echo -e "\033[0m"
    echo "Claude API Setup"
    echo "----------------"
}

# Check if API key is already configured
check_existing_config() {
    if [ -f "$CLAUDE_CONFIG_FILE" ]; then
        if grep -q "api_key" "$CLAUDE_CONFIG_FILE"; then
            echo "Claude API is already configured."
            echo ""
            read -p "Do you want to update the API key? (y/n): " update_key
            if [[ "$update_key" != "y" ]]; then
                echo "Keeping existing configuration."
                exit 0
            fi
        fi
    fi
}

# Request API key from user
request_api_key() {
    echo ""
    echo "To use Claude AI integration, you need an Anthropic API key."
    echo "You can get one by signing up at https://console.anthropic.com/"
    echo ""
    echo "Your API key will be stored locally and not shared."
    echo ""
    
    # Use read -s for secure (hidden) input
    read -s -p "Please enter your Claude API key: " api_key
    echo ""
    
    if [ -z "$api_key" ]; then
        echo "No API key provided. Setup canceled."
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
    
    echo "API key saved securely to $CLAUDE_CONFIG_FILE"
}

# Verify the API key works
verify_api_key() {
    echo "Verifying API key..."
    
    # Extract API key from config file
    api_key=$(grep -o '"api_key": "[^"]*"' "$CLAUDE_CONFIG_FILE" | cut -d'"' -f4)
    
    # Simple test call to Claude API
    response=$(curl -s -w "%{http_code}" -o /tmp/claude_response.txt \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        "https://api.anthropic.com/v1/messages" \
        -d '{
        "model": "claude-3-5-sonnet-20240620",
        "max_tokens": 100,
        "messages": [{"role": "user", "content": "Say hello to TheArchHive"}]
        }')
    
    http_code=${response: -3}
    
    if [[ "$http_code" == "200" ]]; then
        echo "API key verified successfully!"
        echo "Claude is ready to use with TheArchHive."
    else
        echo "API key verification failed with status code: $http_code"
        echo "Error details:"
        cat /tmp/claude_response.txt
        echo ""
        echo "Please check your API key and try again."
        rm -f "$CLAUDE_CONFIG_FILE"
        exit 1
    fi
    
    # Clean up
    rm -f /tmp/claude_response.txt
}

# Configure Neovim integration
configure_neovim() {
    echo "Configuring Neovim integration..."
    
    # Ensure the Claude Neovim plugin is aware of the config file location
    NEOVIM_CONFIG_DIR="$CONFIG_DIR/nvim/lua/claude"
    mkdir -p "$NEOVIM_CONFIG_DIR"
    
    # Create or update the Neovim config to use the API config
    cat > "$NEOVIM_CONFIG_DIR/config.lua" << EOF
-- Claude configuration for Neovim
local M = {}

M.config_path = "$CLAUDE_CONFIG_FILE"
M.api_configured = true

return M
EOF

    echo "Neovim integration configured successfully."
}

# Main script execution
display_banner
check_existing_config
request_api_key
verify_api_key
configure_neovim

echo ""
echo "Setup complete! You can now use Claude in Neovim."
echo "Use <Space>cc to open Claude, and <Space>ca to ask questions."
