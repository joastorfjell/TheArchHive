#!/bin/bash
# TheArchHive - Configuration Permissions Test
# This script checks permissions on configuration files and fixes them if needed

# Configuration
CONFIG_FILE="$HOME/.config/thearchhive/claude_config.json"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
CLAUDE_DIR="$NVIM_CONFIG_DIR/lua/claude"
JSON_MODULE="$NVIM_CONFIG_DIR/lua/json.lua"

# Header
echo "TheArchHive Configuration Permissions Test"
echo "=========================================="
echo ""

# Function to check file
check_file() {
  local file="$1"
  local expected_perm="$2"
  local fix="${3:-n}"
  
  if [ ! -e "$file" ]; then
    echo "❌ File not found: $file"
    return 1
  fi
  
  local perms=$(stat -c "%a" "$file")
  
  if [ "$perms" = "$expected_perm" ]; then
    echo "✅ $file has correct permissions: $perms"
    return 0
  else
    echo "❌ $file has incorrect permissions: $perms (should be $expected_perm)"
    
    if [ "$fix" = "y" ]; then
      echo "   Fixing permissions..."
      chmod $expected_perm "$file"
      echo "   New permissions: $(stat -c "%a" "$file")"
    fi
    
    return 1
  fi
}

# Check if files exist
echo "Checking configuration files..."

# Check API config file
echo -e "\nAPI Configuration File:"
if [ -f "$CONFIG_FILE" ]; then
  echo "Found: $CONFIG_FILE"
  check_file "$CONFIG_FILE" "600" "y"
  
  # Check file content
  echo ""
  echo "Config file content check:"
  if grep -q '"api_key"' "$CONFIG_FILE"; then
    echo "✅ API key entry found"
    
    # Extract API key for preview
    API_KEY=$(grep -o '"api_key": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
    if [ -n "$API_KEY" ]; then
      # Show first 4 and last 4 characters
      echo "API key preview: ${API_KEY:0:4}...${API_KEY: -4}"
    else
      echo "❌ Could not extract API key from config"
    fi
  else
    echo "❌ No API key entry found in config file"
  fi
else
  echo "❌ Config file not found: $CONFIG_FILE"
  echo "   To fix, run: ./scripts/setup-claude.sh"
fi

# Check Neovim Claude module
echo -e "\nNeovim Claude Module:"
if [ -d "$CLAUDE_DIR" ]; then
  echo "Found: $CLAUDE_DIR"
  
  # Check init.lua
  if [ -f "$CLAUDE_DIR/init.lua" ]; then
    echo "Found: $CLAUDE_DIR/init.lua"
    check_file "$CLAUDE_DIR/init.lua" "644" "y"
  else
    echo "❌ Claude init.lua not found: $CLAUDE_DIR/init.lua"
  fi
  
  # Check config.lua
  if [ -f "$CLAUDE_DIR/config.lua" ]; then
    echo "Found: $CLAUDE_DIR/config.lua"
    check_file "$CLAUDE_DIR/config.lua" "644" "y"
    
    # Check config content
    echo ""
    echo "Config module content check:"
    if grep -q "config_path" "$CLAUDE_DIR/config.lua"; then
      echo "✅ config_path entry found"
      
      # Extract config path
      CONFIG_PATH=$(grep -o "config_path = \"[^\"]*\"" "$CLAUDE_DIR/config.lua" | cut -d'"' -f2)
      if [ -n "$CONFIG_PATH" ]; then
        echo "Config path: $CONFIG_PATH"
        
        # Check if the extracted path matches the expected config file
        if [ "$CONFIG_PATH" = "$CONFIG_FILE" ]; then
          echo "✅ Config path is correct"
        else
          echo "❌ Config path mismatch!"
          echo "   Found: $CONFIG_PATH"
          echo "   Expected: $CONFIG_FILE"
        fi
      else
        echo "❌ Could not extract config path"
      fi
    else
      echo "❌ No config_path entry found in config module"
    fi
  else
    echo "❌ Claude config.lua not found: $CLAUDE_DIR/config.lua"
  fi
else
  echo "❌ Claude module directory not found: $CLAUDE_DIR"
  echo "   To fix, run: ./install.sh"
fi

# Check JSON module
echo -e "\nJSON Module:"
if [ -f "$JSON_MODULE" ]; then
  echo "Found: $JSON_MODULE"
  check_file "$JSON_MODULE" "644" "y"
else
  echo "❌ JSON module not found: $JSON_MODULE"
  echo "   To fix, run: ./install.sh"
fi

echo -e "\nTest completed!"
