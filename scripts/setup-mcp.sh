#!/bin/bash
# setup-mcp.sh - Configure and start the MCP server for TheArchHive

set -e  # Exit on error

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration paths
CONFIG_DIR="$HOME/.config/thearchhive"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
DATA_DIR="$HOME/.local/share/thearchhive"
SNAPSHOT_DIR="$DATA_DIR/snapshots"
MCP_SERVER_PATH="$SCRIPTS_DIR/mcp-server.py"
MCP_CONFIG_PATH="$CONFIG_DIR/mcp_config.json"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SYSTEMD_SERVICE="thearchhive-mcp.service"
MCP_PORT=5678

# Log function
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Create directories if they don't exist
create_directories() {
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$SCRIPTS_DIR"
  mkdir -p "$DATA_DIR"
  mkdir -p "$SNAPSHOT_DIR"
  mkdir -p "$SYSTEMD_DIR"
  
  log "✓ Created directory structure"
}

# Check if MCP server exists
check_mcp_server() {
  if [ ! -f "$MCP_SERVER_PATH" ]; then
    log "${RED}MCP server script not found at $MCP_SERVER_PATH${NC}"
    return 1
  fi
  
  log "✓ Found MCP server script"
  return 0
}

# Ensure MCP server is executable
ensure_executable() {
  chmod +x "$MCP_SERVER_PATH"
  log "✓ Made MCP server executable"
}

# Create or update MCP configuration
configure_mcp() {
  if [ ! -f "$MCP_CONFIG_PATH" ]; then
    cat > "$MCP_CONFIG_PATH" << EOF
{
  "port": $MCP_PORT,
  "snapshot_dir": "$SNAPSHOT_DIR",
  "enable_command_execution": false,
  "safe_commands": ["pacman -Qi", "uname", "df", "free", "cat /proc/cpuinfo", "lspci"]
}
EOF
    log "✓ Created MCP configuration"
  else
    log "✓ MCP configuration already exists"
  fi
  
  # Ensure proper permissions
  chmod 600 "$MCP_CONFIG_PATH"
}

# Create systemd service file
create_systemd_service() {
  # Determine which executable to use
  local mcp_exec="$MCP_SERVER_PATH"
  if [ -f "$SCRIPTS_DIR/run_mcp_server.sh" ]; then
    mcp_exec="$SCRIPTS_DIR/run_mcp_server.sh"
  fi
  
  # Create service file
  cat > "$SYSTEMD_DIR/$SYSTEMD_SERVICE" << EOF
[Unit]
Description=TheArchHive MCP Server
After=network.target

[Service]
ExecStart=$mcp_exec
Restart=on-failure
RestartSec=5s
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF
  
  log "✓ Created SystemD service file"
  
  # Reload systemd
  systemctl --user daemon-reload
  log "✓ Reloaded SystemD daemon"
}

# Check Python dependencies
check_dependencies() {
  log "Checking Python dependencies..."
  
  # Try to import required modules
  if python -c "import flask, psutil" 2>/dev/null; then
    log "✓ Required Python modules are installed"
    return 0
  else
    log "${YELLOW}Missing required Python modules. Installing...${NC}"
    
    # Try pip install
    if pip install --user flask psutil; then
      log "✓ Installed required Python modules"
      return 0
    fi
    
    # If regular pip fails, try pip3
    if pip3 install --user flask psutil; then
      log "✓ Installed required Python modules"
      return 0
    fi
    
    # Check if using an externally managed environment
    if pip --version 2>/dev/null | grep -q "externally-managed-environment" || 
       pip3 --version 2>/dev/null | grep -q "externally-managed-environment"; then
      log "${YELLOW}Detected externally managed Python environment${NC}"
      
      # Try using venv
      if python -m venv --help >/dev/null 2>&1; then
        local venv_dir="$DATA_DIR/venv"
        mkdir -p "$(dirname "$venv_dir")"
        
        log "Creating virtual environment at $venv_dir"
        python -m venv "$venv_dir"
        
        # Activate and install
        source "$venv_dir/bin/activate"
        pip install flask psutil
        deactivate
        
        # Create activation script
        cat > "$CONFIG_DIR/activate_venv.sh" << EOV
#!/bin/bash
source "$venv_dir/bin/activate"
EOV
        chmod +x "$CONFIG_DIR/activate_venv.sh"
        
        # Create wrapper script
        cat > "$SCRIPTS_DIR/run_mcp_server.sh" << EOS
#!/bin/bash
source "$CONFIG_DIR/activate_venv.sh"
python "$MCP_SERVER_PATH" "\$@"
EOS
        chmod +x "$SCRIPTS_DIR/run_mcp_server.sh"
        
        log "✓ Set up virtual environment and wrapper script"
        
        # Update systemd service to use wrapper
        create_systemd_service
        return 0
      else
        log "${RED}Python venv module not available. Please install python-venv package${NC}"
        return 1
      fi
    fi
    
    log "${RED}Failed to install required Python modules${NC}"
    return 1
  fi
}

# Enable and start the systemd service
enable_and_start_service() {
  systemctl --user enable "$SYSTEMD_SERVICE"
  systemctl --user restart "$SYSTEMD_SERVICE"
  
  # Check if service started successfully
  sleep 2
  if systemctl --user is-active --quiet "$SYSTEMD_SERVICE"; then
    log "✓ MCP server service is running"
  else
    log "${RED}Failed to start MCP server service${NC}"
    log "Check logs with: systemctl --user status $SYSTEMD_SERVICE"
    return 1
  fi
  
  # Test if MCP server is responding
  sleep 1
  if curl -s http://127.0.0.1:$MCP_PORT/system/info > /dev/null; then
    log "✓ MCP server is responding to requests"
  else
    log "${YELLOW}MCP server is not responding to requests${NC}"
    log "Check logs with: systemctl --user status $SYSTEMD_SERVICE"
    return 1
  fi
  
  return 0
}

# Fix permissions
fix_permissions() {
  # Make sure scripts are executable
  find "$SCRIPTS_DIR" -name "*.py" -type f -exec chmod +x {} \;
  find "$SCRIPTS_DIR" -name "*.sh" -type f -exec chmod +x {} \;
  
  # Ensure config files have correct permissions
  find "$CONFIG_DIR" -name "*.json" -type f -exec chmod 600 {} \;
  
  log "✓ Fixed permissions"
}

# Main function
main() {
  echo -e "${GREEN}Setting up MCP server for TheArchHive${NC}"
  
  create_directories
  
  if ! check_mcp_server; then
    echo -e "${RED}MCP server script not found. Please install TheArchHive first.${NC}"
    exit 1
  fi
  
  ensure_executable
  configure_mcp
  create_systemd_service
  
  if ! check_dependencies; then
    echo -e "${YELLOW}Failed to install dependencies. MCP server may not work correctly.${NC}"
  fi
  
  fix_permissions
  
  if enable_and_start_service; then
    echo -e "${GREEN}MCP server is now set up and running!${NC}"
    echo "Port: $MCP_PORT"
    echo "Configuration: $MCP_CONFIG_PATH"
    echo "Service: $SYSTEMD_SERVICE"
    echo
    echo "You can check its status with: systemctl --user status $SYSTEMD_SERVICE"
    echo "View logs with: journalctl --user -u $SYSTEMD_SERVICE"
  else
    echo -e "${YELLOW}MCP server setup completed with warnings.${NC}"
  fi
}

# Run the main function
main "$@"
