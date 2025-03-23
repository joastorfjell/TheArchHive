#!/bin/bash
# TheArchHive - Setup script for Model Context Protocol (MCP) Server

set -e

echo "Setting up MCP Server for TheArchHive..."

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is required but not installed."
    echo "Please install Python 3 using pacman:"
    echo "sudo pacman -S python python-pip"
    exit 1
fi

# Install psutil
echo "Installing required Python dependencies..."
pip install psutil --user || sudo pip install psutil

# Create directories
mkdir -p ~/.config/thearchhive

# Create default config if it doesn't exist
if [ ! -f ~/.config/thearchhive/mcp_config.json ]; then
    echo "Creating default MCP server configuration..."
    cat > ~/.config/thearchhive/mcp_config.json << EOF
{
  "port": 7424,
  "allowed_commands": ["pacman", "neofetch", "ls", "cat", "grep", "systemctl", "uname", "free", "df"],
  "log_file": "$HOME/.config/thearchhive/mcp.log",
  "debug_mode": false
}
EOF
    echo "Configuration created at: ~/.config/thearchhive/mcp_config.json"
fi

echo "MCP Server setup complete!"
echo ""
echo "To start the MCP server, run:"
echo "python3 scripts/mcp_server.py"
echo ""
echo "The server will run on port 7424 (ARCH on a phone keypad) by default."
echo "You can modify settings in ~/.config/thearchhive/mcp_config.json"
