#!/bin/bash
# TheArchHive - Claude Configuration Migration Script
# This script migrates Claude configuration from the repository to the home directory

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Define paths
OLD_CONFIG_DIR="$PROJECT_ROOT/config/claude"
OLD_CONFIG_FILE="$OLD_CONFIG_DIR/config.json"
NEW_CONFIG_DIR="$HOME/.config/thearchhive"
NEW_CONFIG_FILE="$NEW_CONFIG_DIR/claude_config.json"

echo "TheArchHive - Claude Configuration Migration"
echo "-------------------------------------------"
echo ""

# Check if old config exists
if [ ! -f "$OLD_CONFIG_FILE" ]; then
    echo "No configuration found at old location: $OLD_CONFIG_FILE"
    echo "No migration needed."
    exit 0
fi

# Check if API key exists in old config
if ! grep -q '"api_key"' "$OLD_CONFIG_FILE"; then
    echo "No API key found in old configuration. No migration needed."
    exit 0
fi

echo "Found configuration at: $OLD_CONFIG_FILE"

# Check if new config already exists
if [ -f "$NEW_CONFIG_FILE" ]; then
    echo "Configuration already exists at new location: $NEW_CONFIG_FILE"
    read -p "Overwrite existing configuration? (y/n): " overwrite
    if [[ "$overwrite" != "y" ]]; then
        echo "Migration canceled."
        exit 0
    fi
fi

# Create new config directory
mkdir -p "$NEW_CONFIG_DIR"

# Copy configuration
cp "$OLD_CONFIG_FILE" "$NEW_CONFIG_FILE"

# Set correct permissions
chmod 600 "$NEW_CONFIG_FILE"

echo "Configuration migrated successfully."
echo "Old config: $OLD_CONFIG_FILE"
echo "New config: $NEW_CONFIG_FILE"

# Update Neovim configuration
NEOVIM_CONFIG_DIR="$HOME/.config/nvim/lua/claude"
mkdir -p "$NEOVIM_CONFIG_DIR"

# Update the config module
cat > "$NEOVIM_CONFIG_DIR/config.lua" << EOF
-- Claude configuration for Neovim
local M = {}

M.config_path = "$NEW_CONFIG_FILE"
M.api_configured = true

return M
EOF

echo "Neovim configuration updated to use the new location."

# Ask to remove old configuration
read -p "Remove the old configuration file? (y/n): " remove
if [[ "$remove" == "y" ]]; then
    rm -f "$OLD_CONFIG_FILE"
    echo "Old configuration file removed."
else
    echo "Old configuration file preserved at: $OLD_CONFIG_FILE"
    echo "You can manually remove it later if needed."
fi

echo ""
echo "Migration completed successfully!"
