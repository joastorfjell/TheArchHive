#!/bin/bash
# TheArchHive - Claude configuration checker script

echo "TheArchHive Claude Configuration Checker"
echo "---------------------------------------"
echo ""

# Check Neovim configuration
NVIM_CONFIG_DIR="$HOME/.config/nvim"
CLAUDE_LUA_DIR="$NVIM_CONFIG_DIR/lua/claude"
CLAUDE_CONFIG_MODULE="$CLAUDE_LUA_DIR/config.lua"

echo "Checking Neovim configuration..."
if [ -d "$NVIM_CONFIG_DIR" ]; then
    echo "✓ Neovim config directory exists at: $NVIM_CONFIG_DIR"
else
    echo "✗ Neovim config directory NOT FOUND at: $NVIM_CONFIG_DIR"
fi

if [ -d "$CLAUDE_LUA_DIR" ]; then
    echo "✓ Claude Lua directory exists at: $CLAUDE_LUA_DIR"
else
    echo "✗ Claude Lua directory NOT FOUND at: $CLAUDE_LUA_DIR"
fi

if [ -f "$CLAUDE_CONFIG_MODULE" ]; then
    echo "✓ Claude config module exists at: $CLAUDE_CONFIG_MODULE"
    echo "  Module content:"
    echo "  --------------"
    cat "$CLAUDE_CONFIG_MODULE" | sed 's/^/  /'
    echo ""
    
    # Extract config path from module
    CONFIG_PATH=$(grep -o "M.config_path = \"[^\"]*\"" "$CLAUDE_CONFIG_MODULE" | cut -d'"' -f2)
    if [ -n "$CONFIG_PATH" ]; then
        echo "  Config path from module: $CONFIG_PATH"
    else
        echo "✗ Could not find config_path in module"
    fi
else
    echo "✗ Claude config module NOT FOUND at: $CLAUDE_CONFIG_MODULE"
fi

# Check JSON module
JSON_MODULE="$NVIM_CONFIG_DIR/lua/json.lua"
if [ -f "$JSON_MODULE" ]; then
    echo "✓ JSON module exists at: $JSON_MODULE"
else
    echo "✗ JSON module NOT FOUND at: $JSON_MODULE"
fi

# Check Claude API config
if [ -n "$CONFIG_PATH" ]; then
    echo ""
    echo "Checking Claude API configuration..."
    if [ -f "$CONFIG_PATH" ]; then
        echo "✓ Claude API config file exists at: $CONFIG_PATH"
        echo "  Config file content:"
        echo "  -------------------"
        cat "$CONFIG_PATH" | sed 's/^/  /'
        echo ""
        
        # Check file permissions
        PERMS=$(stat -c "%a" "$CONFIG_PATH")
        echo "  File permissions: $PERMS"
        if [[ "$PERMS" == "600" ]]; then
            echo "✓ File permissions are correct"
        else
            echo "✗ File permissions should be 600, not $PERMS"
            echo "  To fix: chmod 600 $CONFIG_PATH"
        fi
        
        # Check if API key exists in config
        if grep -q "\"api_key\":" "$CONFIG_PATH"; then
            echo "✓ API key entry found in config file"
        else
            echo "✗ No API key entry found in config file"
        fi
    else
        echo "✗ Claude API config file NOT FOUND at: $CONFIG_PATH"
    fi
else
    echo ""
    echo "Checking Claude API configuration..."
    echo "✗ Could not determine Claude API config path"
fi

echo ""
echo "Troubleshooting suggestions:"
echo "1. If any files are missing, re-run the installation script: ./install.sh"
echo "2. If the API config file is missing, re-run the Claude setup: ./scripts/setup-claude.sh"
echo "3. If the API key is missing from config, check the Claude setup script output"
echo "4. Make sure file permissions are correct for the config file (chmod 600)"
