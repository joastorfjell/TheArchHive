#!/bin/bash
# TheArchHive Installation Script
# Sets up all components for the TheArchHive project

set -e  # Exit on error

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_DIR="$SCRIPT_DIR"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="$HOME/.config/thearchhive"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
DATA_DIR="$HOME/.local/share/thearchhive"
BACKUP_DIR="$DATA_DIR/backups"
SNAPSHOT_DIR="$DATA_DIR/snapshots"
VENV_DIR="$DATA_DIR/venv"
MCP_PORT=5678
NVIM_CONFIG_DIR="$HOME/.config/nvim"
CLAUDESCRIPT_PATH="$SCRIPTS_DIR/ClaudeScript.py"
OPERATING_TOOLS_PATH="$SCRIPTS_DIR/OperatingTools.py"

# Function to handle Python module installation with externally-managed-environment handling
install_python_modules() {
    local modules=("$@")
    
    # First try with regular pip
    echo "Attempting to install Python modules with pip..."
    if pip install --user "${modules[@]}" 2>/dev/null; then
        echo "Successfully installed modules with pip"
        return 0
    fi
    
    # If that fails, try with pip3
    echo "Attempting to install Python modules with pip3..."
    if pip3 install --user "${modules[@]}" 2>/dev/null; then
        echo "Successfully installed modules with pip3"
        return 0
    fi
    
    # Check if we're running in an externally managed environment
    if pip --version 2>/dev/null | grep -q "externally-managed-environment" || 
       pip3 --version 2>/dev/null | grep -q "externally-managed-environment"; then
        echo "Detected externally managed Python environment"
        
        # Try package manager first
        echo "Attempting to install modules via package manager..."
        local pkg_prefixes=("python-" "python3-")
        local pkg_names=()
        
        for module in "${modules[@]}"; do
            for prefix in "${pkg_prefixes[@]}"; do
                pkg_names+=("$prefix$module")
            done
        done
        
        if sudo pacman -S --needed "${pkg_names[@]}" 2>/dev/null; then
            echo "Successfully installed modules via package manager"
            return 0
        fi
        
        # Try virtual environment approach
        echo "Installing modules in a virtual environment..."
        
        # Check if venv module is available
        if python -m venv --help >/dev/null 2>&1; then
            mkdir -p "$(dirname "$VENV_DIR")"
            
            # Create virtual environment
            python -m venv "$VENV_DIR"
            
            # Activate and install
            source "$VENV_DIR/bin/activate"
            pip install "${modules[@]}"
            deactivate
            
            # Add activation to configuration
            mkdir -p "$CONFIG_DIR"
            echo "source $VENV_DIR/bin/activate" > "$CONFIG_DIR/activate_venv.sh"
            chmod +x "$CONFIG_DIR/activate_venv.sh"
            
            # Create wrapper script for MCP server
            mkdir -p "$SCRIPTS_DIR"
            
            cat > "$SCRIPTS_DIR/run_mcp_server.sh" << 'EOF'
#!/bin/bash
source "$HOME/.config/thearchhive/activate_venv.sh"
python "$HOME/.config/thearchhive/scripts/mcp-server.py" "$@"
EOF
            chmod +x "$SCRIPTS_DIR/run_mcp_server.sh"
            
            # Update systemd service to use wrapper
            local systemd_dir="$HOME/.config/systemd/user"
            if [ -f "$systemd_dir/thearchhive-mcp.service" ]; then
                sed -i 's|ExecStart=/usr/bin/python.*|ExecStart='"$SCRIPTS_DIR"'/run_mcp_server.sh|' "$systemd_dir/thearchhive-mcp.service"
                systemctl --user daemon-reload
            fi
            
            echo "Successfully installed modules in virtual environment"
            echo "Use $CONFIG_DIR/activate_venv.sh to activate the environment when needed"
            return 0
        else
            echo "Python venv module not available. Please install python-venv package"
            return 1
        fi
    fi
    
    echo "Failed to install Python modules"
    return 1
}

# Log function
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Print section header
section_header() {
  echo -e "\n${GREEN}=== $1 ===${NC}"
}

# Prompt user for input
prompt() {
  read -p "$1 " "$2"
}

# Check system requirements
# Check system requirements
check_requirements() {
  section_header "Checking System Requirements"
  
  # Check if running on Arch Linux
  if [ -f /etc/arch-release ]; then
    log "✓ Running on Arch Linux"
  else
    log "${YELLOW}Warning: Not running on Arch Linux. Some features may not work correctly.${NC}"
  fi
  
  # Check for required commands
  local requirements=("git" "python" "nvim" "curl" "jq" "tmux")
  local missing_requirements=()
  
  for cmd in "${requirements[@]}"; do
    if command_exists "$cmd"; then
      log "✓ Found $cmd"
    else
      log "${RED}✗ Missing $cmd${NC}"
      missing_requirements+=("$cmd")
    fi
  done
  
  if [ ${#missing_requirements[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing required packages. Install them with:${NC}"
    echo -e "sudo pacman -S ${missing_requirements[*]}"
    
    prompt "Install missing packages now? (y/n)" INSTALL_PACKAGES
    if [[ "$INSTALL_PACKAGES" =~ ^[Yy]$ ]]; then
      sudo pacman -S "${missing_requirements[@]}"
    else
      echo -e "${YELLOW}Continuing installation without required packages. Some features may not work.${NC}"
    fi
  fi
  
  # Check for Python modules
  local python_modules=("flask" "psutil")
  local missing_modules=()
  
  for module in "${python_modules[@]}"; do
    if python -c "import $module" 2>/dev/null; then
      log "✓ Found Python module $module"
    else
      log "${RED}✗ Missing Python module $module${NC}"
      missing_modules+=("$module")
    fi
  done
  
  if [ ${#missing_modules[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing required Python modules. Install them with:${NC}"
    echo -e "pip install ${missing_modules[*]}"
    
    prompt "Install missing Python modules now? (y/n)" INSTALL_MODULES
    if [[ "$INSTALL_MODULES" =~ ^[Yy]$ ]]; then
      install_python_modules "${missing_modules[@]}"
    else
      echo -e "${YELLOW}Continuing installation without required Python modules. Some features may not work.${NC}"
    fi
  fi
}

# Create directory structure
create_directories() {
  section_header "Creating Directory Structure"
  
  mkdir -p "$CONFIG_DIR"
  mkdir -p "$SCRIPTS_DIR"
  mkdir -p "$DATA_DIR"
  mkdir -p "$BACKUP_DIR"
  mkdir -p "$SNAPSHOT_DIR"
  mkdir -p "$NVIM_CONFIG_DIR/lua/claude"
  
  log "✓ Created directory structure"
}

# Install scripts
install_scripts() {
  section_header "Installing Scripts"
  
  # Locate the MCP server
  MCP_SERVER_PATH=""
  POSSIBLE_PATHS=(
    "$REPO_DIR/mcp-server.py"
    "$REPO_DIR/scripts/mcp-server.py"
    "$REPO_DIR/src/mcp-server.py"
  )
  
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
      MCP_SERVER_PATH="$path"
      break
    fi
  done
  
  if [ -z "$MCP_SERVER_PATH" ]; then
    log "${YELLOW}Warning: MCP server script not found. Creating a placeholder.${NC}"
    # Create a basic placeholder that will show an error if run
    cat > "$SCRIPTS_DIR/mcp-server.py" << EOF
#!/usr/bin/env python3
print("Error: This is a placeholder MCP server. The actual script was not found during installation.")
print("Please create a proper MCP server implementation.")
exit(1)
EOF
  else
    # Copy MCP server
    cat "$MCP_SERVER_PATH" > "$SCRIPTS_DIR/mcp-server.py"
    log "✓ Installed MCP server from $MCP_SERVER_PATH"
  fi
  chmod +x "$SCRIPTS_DIR/mcp-server.py"
  
  # Locate the ClaudeScript implementation
  CLAUDESCRIPT_SRC_PATH=""
  POSSIBLE_PATHS=(
    "$REPO_DIR/claudescript.py"
    "$REPO_DIR/scripts/claudescript.py"
    "$REPO_DIR/ClaudeScript.py"
    "$REPO_DIR/scripts/ClaudeScript.py"
  )
  
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
      CLAUDESCRIPT_SRC_PATH="$path"
      break
    fi
  done
  
  if [ -z "$CLAUDESCRIPT_SRC_PATH" ]; then
    log "${YELLOW}Warning: ClaudeScript implementation not found. Creating a placeholder.${NC}"
    # Create a basic placeholder
    cat > "$CLAUDESCRIPT_PATH" << EOF
#!/usr/bin/env python3
print("Error: This is a placeholder ClaudeScript implementation. The actual script was not found during installation.")
print("Please create a proper ClaudeScript implementation.")
exit(1)
EOF
  else
    # Copy ClaudeScript implementation
    cat "$CLAUDESCRIPT_SRC_PATH" > "$CLAUDESCRIPT_PATH"
    log "✓ Installed ClaudeScript implementation from $CLAUDESCRIPT_SRC_PATH"
  fi
  chmod +x "$CLAUDESCRIPT_PATH"
  
  # Locate the Operating Tools implementation
  OPERATING_TOOLS_SRC_PATH=""
  POSSIBLE_PATHS=(
    "$REPO_DIR/OperatingTools.py"
    "$REPO_DIR/scripts/OperatingTools.py"
  )
  
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
      OPERATING_TOOLS_SRC_PATH="$path"
      break
    fi
  done
  
  if [ -z "$OPERATING_TOOLS_SRC_PATH" ]; then
    log "${YELLOW}Warning: Operating Tools implementation not found. Creating a placeholder.${NC}"
    # Create a basic placeholder
    cat > "$OPERATING_TOOLS_PATH" << EOF
#!/usr/bin/env python3
print("Error: This is a placeholder Operating Tools implementation. The actual script was not found during installation.")
print("Please create a proper Operating Tools implementation.")
exit(1)
EOF
  else
    # Copy Operating Tools implementation
    cat "$OPERATING_TOOLS_SRC_PATH" > "$OPERATING_TOOLS_PATH"
    log "✓ Installed Operating Tools from $OPERATING_TOOLS_SRC_PATH"
  fi
  chmod +x "$OPERATING_TOOLS_PATH"
  
  # Similar process for backup script
  BACKUP_SCRIPT_PATH=""
  POSSIBLE_PATHS=(
    "$REPO_DIR/backup.sh"
    "$REPO_DIR/scripts/backup.sh"
  )
  
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
      BACKUP_SCRIPT_PATH="$path"
      break
    fi
  done
  
  if [ -z "$BACKUP_SCRIPT_PATH" ]; then
    log "${YELLOW}Warning: Backup script not found. Creating a placeholder.${NC}"
    # Create a basic placeholder
    cat > "$SCRIPTS_DIR/backup.sh" << EOF
#!/bin/bash
echo "Error: This is a placeholder backup script. The actual script was not found during installation."
echo "Please create a proper backup script implementation."
exit 1
EOF
  else
    # Copy backup script
    cat "$BACKUP_SCRIPT_PATH" > "$SCRIPTS_DIR/backup.sh"
    log "✓ Installed backup script from $BACKUP_SCRIPT_PATH"
  fi
  chmod +x "$SCRIPTS_DIR/backup.sh"
  
  # Create MCP configuration
  cat > "$CONFIG_DIR/mcp_config.json" << EOF
{
  "port": $MCP_PORT,
  "snapshot_dir": "$SNAPSHOT_DIR",
  "enable_command_execution": false,
  "safe_commands": ["pacman -Qi", "uname", "df", "free", "cat /proc/cpuinfo", "lspci"]
}
EOF
  log "✓ Created MCP configuration"
  
  # Create backup configuration
  cat > "$CONFIG_DIR/backup_config.json" << EOF
{
  "backup_repo": "$BACKUP_DIR",
  "git_remote": "",
  "config_files": [
    "$NVIM_CONFIG_DIR/init.vim",
    "$NVIM_CONFIG_DIR/lua/claude",
    "$CONFIG_DIR",
    "$HOME/.bashrc",
    "$HOME/.zshrc",
    "$HOME/.xinitrc",
    "$HOME/.Xresources"
  ]
}
EOF
  log "✓ Created backup configuration"
  
  # Create MCP server wrapper script if using virtual environment
  if [ -f "$CONFIG_DIR/activate_venv.sh" ]; then
    cat > "$SCRIPTS_DIR/run_mcp_server.sh" << EOF
#!/bin/bash
source "$CONFIG_DIR/activate_venv.sh"
python "$SCRIPTS_DIR/mcp-server.py" "\$@"
EOF
    chmod +x "$SCRIPTS_DIR/run_mcp_server.sh"
    log "✓ Created MCP server wrapper script for virtual environment"
  fi
}

# Configure Neovim
configure_neovim() {
  section_header "Configuring Neovim"
  
  # Look for Neovim templates
  local neovim_templates_dir=""
  local possible_dirs=(
    "$REPO_DIR/neovim-templates"
    "$REPO_DIR/config/nvim"
  )
  
  for dir in "${possible_dirs[@]}"; do
    if [ -d "$dir" ]; then
      neovim_templates_dir="$dir"
      break
    fi
  done
  
  # Create or update init.vim
  if [ -n "$neovim_templates_dir" ] && [ -f "$neovim_templates_dir/init.vim" ]; then
    # Copy the template init.vim
    mkdir -p "$NVIM_CONFIG_DIR"
    cp "$neovim_templates_dir/init.vim" "$NVIM_CONFIG_DIR/init.vim"
    log "✓ Installed init.vim from template"
  elif [ ! -f "$NVIM_CONFIG_DIR/init.vim" ]; then
    # Create a basic init.vim if no template exists
    cat > "$NVIM_CONFIG_DIR/init.vim" << EOF
" TheArchHive Neovim Configuration
" Basic settings
set number
set relativenumber
set expandtab
set tabstop=2
set shiftwidth=2
set softtabstop=2
set autoindent
set smartindent
set cursorline
set showcmd
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set splitbelow
set splitright
set hidden
set termguicolors
set scrolloff=5
set mouse=a
set clipboard=unnamedplus
set updatetime=300
set timeoutlen=500

" Key mappings
let mapleader = " "
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>
nnoremap <leader>e :e ~/.config/nvim/init.vim<CR>
nnoremap <leader>so :source ~/.config/nvim/init.vim<CR>

" Lua configuration
lua require('claude').setup()
EOF
    log "✓ Created default init.vim"
  else
    # Check if Claude setup is in init.vim
    if ! grep -q "require('claude').setup()" "$NVIM_CONFIG_DIR/init.vim"; then
      echo -e "\n\" TheArchHive Claude Integration\nlua require('claude').setup()" >> "$NVIM_CONFIG_DIR/init.vim"
      log "✓ Updated init.vim with Claude integration"
    else
      log "✓ Claude integration already in init.vim"
    fi
  fi
  
  # Copy Lua modules from templates if available
  if [ -n "$neovim_templates_dir" ] && [ -d "$neovim_templates_dir/lua" ]; then
    mkdir -p "$NVIM_CONFIG_DIR/lua"
    
    # Copy all template Lua modules except claude directory
    for item in "$neovim_templates_dir/lua"/*; do
      if [ -d "$item" ] && [ "$(basename "$item")" != "claude" ]; then
        cp -r "$item" "$NVIM_CONFIG_DIR/lua/"
        log "✓ Installed Lua module: $(basename "$item")"
      elif [ -f "$item" ]; then
        cp "$item" "$NVIM_CONFIG_DIR/lua/"
        log "✓ Installed Lua file: $(basename "$item")"
      fi
    done
    
    # Copy claude/json.lua if it exists
    if [ -f "$neovim_templates_dir/lua/claude/json.lua" ]; then
      mkdir -p "$NVIM_CONFIG_DIR/lua/claude"
      cp "$neovim_templates_dir/lua/claude/json.lua" "$NVIM_CONFIG_DIR/lua/claude/json.lua"
      log "✓ Installed claude/json.lua from template"
    fi
  fi
  
  # Install Claude Lua module
  mkdir -p "$NVIM_CONFIG_DIR/lua/claude"
  
  # Create Claude configuration module if it doesn't exist
  if [ ! -f "$NVIM_CONFIG_DIR/lua/claude/config.lua" ]; then
    cat > "$NVIM_CONFIG_DIR/lua/claude/config.lua" << EOF
local M = {}

function M.load_claude_config()
  local config_dir = os.getenv("HOME") .. "/.config/thearchhive"
  local config_file = config_dir .. "/claude_config.json"
  
  -- Check if file exists
  local f = io.open(config_file, "r")
  if not f then
    return nil
  end
  
  local content = f:read("*all")
  f:close()
  
  local ok, config = pcall(function()
    return require("claude.json").decode(content)
  end)
  
  if not ok then
    print("Error loading Claude configuration: " .. tostring(config))
    return nil
  end
  
  return config
end

return M
EOF
    log "✓ Created Claude configuration module"
  fi
  
  # Create JSON parser module if needed
  if [ ! -f "$NVIM_CONFIG_DIR/lua/claude/json.lua" ]; then
    cat > "$NVIM_CONFIG_DIR/lua/claude/json.lua" << EOF
local json = {}

function json.decode(str)
  local status, result = pcall(vim.fn.json_decode, str)
  if status then
    return result
  else
    error("JSON decode error: " .. result)
    return nil
  end
end

function json.encode(data)
  local status, result = pcall(vim.fn.json_encode, data)
  if status then
    return result
  else
    error("JSON encode error: " .. result)
    return nil
  end
end

return json
EOF
    log "✓ Created JSON parser module"
  fi
  
  # Locate the Claude integration implementation
  CLAUDE_INTEGRATION_PATH=""
  POSSIBLE_PATHS=(
    "$REPO_DIR/claude-mcp-integration.lua"
    "$REPO_DIR/scripts/claude-mcp-integration.lua"
    "$neovim_templates_dir/lua/claude/init.lua"
  )
  
  for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -f "$path" ]; then
      CLAUDE_INTEGRATION_PATH="$path"
      break
    fi
  done
  
  if [ -z "$CLAUDE_INTEGRATION_PATH" ]; then
    log "${YELLOW}Warning: Claude Neovim integration not found. Creating a placeholder.${NC}"
    # Create a basic placeholder
    cat > "$NVIM_CONFIG_DIR/lua/claude/init.lua" << EOF
-- Placeholder Claude integration module
local M = {}

function M.setup()
  vim.api.nvim_create_user_command('Claude', function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "Claude Integration Error",
      "",
      "This is a placeholder Claude integration module.",
      "The actual implementation was not found during installation.",
      "",
      "Please install the proper Claude integration implementation."
    })
    vim.api.nvim_set_current_buf(buf)
  end, {})
end

return M
EOF
  else
    # Copy Claude Neovim integration
    cat "$CLAUDE_INTEGRATION_PATH" > "$NVIM_CONFIG_DIR/lua/claude/init.lua"
    log "✓ Installed Claude Neovim integration from $CLAUDE_INTEGRATION_PATH"
  fi
  
  # Create plenary dependency if needed
  if [ ! -d "$NVIM_CONFIG_DIR/pack/plugins/start/plenary.nvim" ]; then
    mkdir -p "$NVIM_CONFIG_DIR/pack/plugins/start"
    git clone https://github.com/nvim-lua/plenary.nvim.git "$NVIM_CONFIG_DIR/pack/plugins/start/plenary.nvim"
    log "✓ Installed plenary.nvim dependency"
  fi
}

# Configure Claude API
configure_claude() {
  section_header "Configuring Claude API"
  
  # Check if config exists
  if [ -f "$CONFIG_DIR/claude_config.json" ]; then
    log "Claude API configuration already exists"
    prompt "Do you want to update it? (y/n)" UPDATE_CONFIG
    if [[ ! "$UPDATE_CONFIG" =~ ^[Yy]$ ]]; then
      return
    fi
  fi
  
  # Prompt for API key
  prompt "Enter your Claude API key:" API_KEY
  
  if [ -z "$API_KEY" ]; then
    log "${YELLOW}No API key provided. Claude API integration will not work.${NC}"
    return
  fi
  
  # Create Claude configuration
  cat > "$CONFIG_DIR/claude_config.json" << EOF
{
  "claude_api_key": "$API_KEY",
  "claude_model": "claude-3-7-sonnet-20250219",
  "max_tokens": 4096,
  "history_size": 10,
  "mcp_url": "http://127.0.0.1:$MCP_PORT"
}
EOF
  chmod 600 "$CONFIG_DIR/claude_config.json"
  log "✓ Created Claude API configuration"
}

# Create SystemD service for MCP server
create_systemd_service() {
  section_header "Creating SystemD Service for MCP Server"
  
  # Create user systemd directory if it doesn't exist
  local systemd_dir="$HOME/.config/systemd/user"
  mkdir -p "$systemd_dir"
  
  # Determine which executable to use
  local mcp_exec="$SCRIPTS_DIR/mcp-server.py"
  if [ -f "$SCRIPTS_DIR/run_mcp_server.sh" ]; then
    mcp_exec="$SCRIPTS_DIR/run_mcp_server.sh"
  fi
  
  # Create service file
  cat > "$systemd_dir/thearchhive-mcp.service" << EOF
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
  
  # Enable and start the service
  systemctl --user daemon-reload
  systemctl --user enable thearchhive-mcp.service
  systemctl --user start thearchhive-mcp.service
  
  log "✓ Enabled and started MCP server service"
}

# Create initial system snapshot
create_initial_snapshot() {
  section_header "Creating Initial System Snapshot"
  
  # Run ClaudeScript snapshot command
  python "$CLAUDESCRIPT_PATH" snapshot --output "$SNAPSHOT_DIR/initial_snapshot_$(date +%Y%m%d%H%M%S).txt"
  log "✓ Created initial system snapshot"
}

# Create desktop entry for TheArchHive Claude
create_desktop_entry() {
  section_header "Creating Desktop Entry"
  
  # Create desktop entry directory if it doesn't exist
  local desktop_dir="$HOME/.local/share/applications"
  mkdir -p "$desktop_dir"
  
  # Create desktop entry file
  cat > "$desktop_dir/thearchhive-claude.desktop" << EOF
[Desktop Entry]
Name=TheArchHive Claude
Comment=Arch Linux Configuration Assistant
Exec=nvim -c Claude
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Utility;Development;
EOF
  
  log "✓ Created desktop entry for TheArchHive Claude"
}

# Print usage information
print_usage() {
  cat << EOF
This script installs TheArchHive, an AI-assisted Arch Linux configuration system.

Usage: ./install.sh [options]

Options:
  --no-nvim       Skip Neovim configuration
  --no-systemd    Skip SystemD service creation
  --no-backup     Skip backup system setup
  --help          Show this help message

EOF
}

# Display summary and next steps
display_summary() {
  section_header "Installation Complete"
  
  echo -e "${GREEN}TheArchHive has been successfully installed!${NC}"
  echo
  echo "Components installed:"
  echo "  ✓ MCP Server"
  echo "  ✓ Claude Neovim Integration"
  echo "  ✓ ClaudeScript Implementation"
  echo "  ✓ Standard Operating Tools"
  echo "  ✓ Backup System"
  echo "  ✓ System Snapshot Tool"
  echo
  if [ -f "$CONFIG_DIR/activate_venv.sh" ]; then
    echo "Python modules installed in virtual environment:"
    echo "  Location: $VENV_DIR"
    echo "  Activation script: $CONFIG_DIR/activate_venv.sh"
    echo
  fi
  echo "Next steps:"
  echo "  1. Start Neovim and run :Claude to open the Claude interface"
  echo "  2. Ask Claude to suggest configurations for your system"
  echo "  3. Run the backup system with: $SCRIPTS_DIR/backup.sh"
  echo "  4. Create system snapshots with: python $CLAUDESCRIPT_PATH snapshot"
  echo
  echo "To update your configuration, edit:"
  echo "  MCP Config: $CONFIG_DIR/mcp_config.json"
  echo "  Backup Config: $CONFIG_DIR/backup_config.json"
  echo "  Claude Config: $CONFIG_DIR/claude_config.json"
  echo
  echo -e "${BLUE}Enjoy using TheArchHive!${NC}"
}

# Main installation function
main() {
  # Process command line arguments
  SKIP_NVIM=false
  SKIP_SYSTEMD=false
  SKIP_BACKUP=false
  
  for arg in "$@"; do
    case $arg in
      --no-nvim)
        SKIP_NVIM=true
        shift
        ;;
      --no-systemd)
        SKIP_SYSTEMD=true
        shift
        ;;
      --no-backup)
        SKIP_BACKUP=true
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      *)
        echo "Unknown option: $arg"
        print_usage
        exit 1
        ;;
    esac
  done
  
  echo -e "${GREEN}TheArchHive Installation${NC}"
  echo "This script will install TheArchHive components on your system."
  
  # Check requirements
  check_requirements
  
  # Create directories
  create_directories
  
  # Install scripts
  install_scripts
  
  # Configure Neovim
  if [ "$SKIP_NVIM" = false ]; then
    configure_neovim
  else
    log "Skipping Neovim configuration"
  fi
  
  # Configure Claude API
  configure_claude
  
  # Create SystemD service
  if [ "$SKIP_SYSTEMD" = false ]; then
    create_systemd_service
  else
    log "Skipping SystemD service creation"
  fi
  
  # Initialize backup system
  if [ "$SKIP_BACKUP" = false ]; then
    "$SCRIPTS_DIR/backup.sh" status
  else
    log "Skipping backup system initialization"
  fi
  
  # Create initial system snapshot
  create_initial_snapshot
  
  # Create desktop entry
  create_desktop_entry
  
  # Display summary
  display_summary
}

# Run the main function
main "$@"
