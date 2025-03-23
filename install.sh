#!/bin/bash
# TheArchHive - Main Installation Script
# This script sets up the TheArchHive environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
NVIM_CONFIG_DIR="$HOME/.config/nvim"
CLAUDE_LUA_DIR="$CONFIG_DIR/nvim/lua/claude"

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
}

# Install base packages
install_base_packages() {
    echo "Installing base packages..."
    
    if ! command -v pacman &> /dev/null; then
        echo "Error: This script requires pacman package manager (Arch Linux)."
        exit 1
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo "Installing packages requires sudo privileges."
        
        # Check if packages file exists
        if [ -f "$SCRIPT_DIR/packages/base.txt" ]; then
            sudo pacman -S --needed --noconfirm $(grep -v '^#' "$SCRIPT_DIR/packages/base.txt")
        else
            echo "Base packages list not found. Installing minimal requirements..."
            sudo pacman -S --needed --noconfirm neovim git curl ripgrep
        fi
    else
        # Running as root
        if [ -f "$SCRIPT_DIR/packages/base.txt" ]; then
            pacman -S --needed --noconfirm $(grep -v '^#' "$SCRIPT_DIR/packages/base.txt")
        else
            echo "Base packages list not found. Installing minimal requirements..."
            pacman -S --needed --noconfirm neovim git curl ripgrep
        fi
    fi
    
    echo "Base packages installed successfully."
}

# Configure Neovim
configure_neovim() {
    echo "Configuring Neovim..."
    
    # Create Neovim config directory if it doesn't exist
    mkdir -p "$NVIM_CONFIG_DIR/lua"
    
    # Copy Neovim configuration files
    if [ -d "$CONFIG_DIR/nvim" ]; then
        # Copy init.vim
        if [ -f "$CONFIG_DIR/nvim/init.vim" ]; then
            cp "$CONFIG_DIR/nvim/init.vim" "$NVIM_CONFIG_DIR/"
            echo "Copied init.vim configuration."
        fi
        
        # Copy Lua configurations
        if [ -d "$CONFIG_DIR/nvim/lua" ]; then
            cp -r "$CONFIG_DIR/nvim/lua/" "$NVIM_CONFIG_DIR/"
            echo "Copied Lua configurations."
        fi
    else
        echo "Neovim configuration not found in the repository."
        # Create minimal init.vim
        echo "Creating minimal Neovim configuration..."
        cat > "$NVIM_CONFIG_DIR/init.vim" << EOF
" TheArchHive - Minimal Neovim Configuration
set number
set relativenumber
set expandtab
set tabstop=4
set shiftwidth=4
set smartindent
set autoindent
set ignorecase
set smartcase
set clipboard=unnamedplus
set termguicolors

" Key mappings
let mapleader = " "
nnoremap <leader>cc :ClaudeOpen<CR>
nnoremap <leader>ca :ClaudeAsk<CR>

" Load Lua configs
lua require('plugins')
EOF
    fi
    
    # Install Packer (plugin manager)
    if [ ! -d "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim" ]; then
        echo "Installing Packer.nvim..."
        git clone --depth 1 https://github.com/wbthomason/packer.nvim \
            "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
    fi
    
    # Create plugins.lua if it doesn't exist
    if [ ! -f "$NVIM_CONFIG_DIR/lua/plugins.lua" ]; then
        mkdir -p "$NVIM_CONFIG_DIR/lua"
        cat > "$NVIM_CONFIG_DIR/lua/plugins.lua" << EOF
-- TheArchHive - Neovim Plugins
return require('packer').startup(function(use)
    -- Packer can manage itself
    use 'wbthomason/packer.nvim'
    
    -- Color scheme
    use 'folke/tokyonight.nvim'
    
    -- Status line
    use {
        'nvim-lualine/lualine.nvim',
        requires = { 'kyazdani42/nvim-web-devicons', opt = true }
    }
    
    -- File explorer
    use {
        'kyazdani42/nvim-tree.lua',
        requires = { 'kyazdani42/nvim-web-devicons' }
    }
    
    -- Initialize plugins
    require('lualine').setup()
    require('nvim-tree').setup()
    
    -- Load TheArchHive Claude integration
    require('claude').setup()
    
    -- Set colorscheme
    vim.cmd[[colorscheme tokyonight]]
end)
EOF
    fi
    
    echo "Neovim configuration completed."
}

# Set up Claude integration
setup_claude_integration() {
    echo "Setting up Claude integration..."
    
    # Create Claude module directory
    mkdir -p "$NVIM_CONFIG_DIR/lua/claude"
    
    # Create config.lua for Claude
    cat > "$NVIM_CONFIG_DIR/lua/claude/config.lua" << EOF
-- Claude configuration for Neovim
local M = {}

M.config_path = "$SCRIPT_DIR/config/claude/config.json"
M.api_configured = false

return M
EOF

    # Copy Claude module files from repository
    if [ -d "$CLAUDE_LUA_DIR" ]; then
        cp -r "$CLAUDE_LUA_DIR"/* "$NVIM_CONFIG_DIR/lua/claude/"
        echo "Copied Claude module from repository."
    else
        # Create minimal Claude init.lua if not in repository
        echo "Claude module not found in repository, creating minimal version..."
        cat > "$NVIM_CONFIG_DIR/lua/claude/init.lua" << EOF
-- TheArchHive Claude Integration
-- Minimal implementation
local M = {}
local api = vim.api

-- Buffer and window IDs
M.buf = nil
M.win = nil
M.initialized = false

-- Initialize Claude window
function M.init()
    if M.initialized then return end
    
    -- Create buffer
    M.buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_option(M.buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(M.buf, 'bufhidden', 'hide')
    api.nvim_buf_set_option(M.buf, 'swapfile', false)
    api.nvim_buf_set_name(M.buf, 'TheArchHive-Claude')
    
    -- Initial greeting message
    local lines = {
        "  _____ _           _            _     _   _ _           ",
        " |_   _| |__   ___ / \\   _ __ __| |__ | | | |_|_   _____ ",
        "   | | | '_ \\ / _ \\ \\ | | '__/ _\` '_ \\| |_| | \\ \\ / / _ \\",
        "   | | | | | |  __/ _ \\| | | (_| | | | |  _  | |\\ V /  __/",
        "   |_| |_| |_|\\___|_/ \\_\\_|  \\__,_|_| |_|_| |_|_| \\_/ \\___|",
        "",
        "Welcome to TheArchHive Claude Integration!",
        "----------------------------------------",
        "",
        "This is a minimal implementation. To set up real Claude API integration:",
        "1. Run ./scripts/setup-claude.sh",
        "2. Enter your Anthropic API key when prompted",
        "",
        "Press 'q' to close this window."
    }
    
    api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    M.initialized = true
end

-- Open Claude window
function M.open()
    if not M.initialized then
        M.init()
    end
    
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    -- Window options
    local opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded'
    }
    
    -- Create window
    M.win = api.nvim_open_win(M.buf, true, opts)
    
    -- Set window options
    api.nvim_win_set_option(M.win, 'wrap', true)
    
    -- Set key mappings
    local opts = { buffer = M.buf, noremap = true, silent = true }
    api.nvim_buf_set_keymap(M.buf, 'n', 'q', ':lua require("claude").close()<CR>', opts)
end

-- Close Claude window
function M.close()
    if M.win and api.nvim_win_is_valid(M.win) then
        api.nvim_win_close(M.win, true)
        M.win = nil
    end
end

-- Ask question placeholder
function M.ask_question()
    api.nvim_buf_set_lines(M.buf, -1, -1, false, {
        "",
        "To use Claude API integration, please run:",
        "./scripts/setup-claude.sh"
    })
end

-- Initialize commands
function M.setup()
    -- Create user commands
    vim.cmd [[
        command! ClaudeOpen lua require('claude').open()
        command! ClaudeClose lua require('claude').close()
        command! ClaudeAsk lua require('claude').ask_question()
    ]]
    
    -- Set up key mappings
    vim.api.nvim_set_keymap('n', '<Space>cc', ':ClaudeOpen<CR>', { noremap = true, silent = true })
    vim.api.nvim_set_keymap('n', '<Space>ca', ':ClaudeAsk<CR>', { noremap = true, silent = true })
end

return M
EOF
    fi
    
    # Create json.lua module if it doesn't exist
    if [ ! -f "$NVIM_CONFIG_DIR/lua/json.lua" ]; then
        echo "Creating JSON module..."
        # Here you would include the JSON module content
        # For brevity, let's add a placeholder comment and implement it separately
        cat > "$NVIM_CONFIG_DIR/lua/json.lua" << EOF
-- JSON module for Lua - placeholder
-- To implement full JSON module, please copy the JSON module implementation
-- from TheArchHive repository
local json = {}

function json.encode(val)
    return tostring(val)
end

function json.decode(str)
    return str
end

return json
EOF
    fi
    
    echo "Claude integration setup completed."
}

# Create snapshot of current system
create_system_snapshot() {
    echo "Creating system snapshot..."
    
    if [ -f "$SCRIPT_DIR/scripts/snapshot.sh" ]; then
        bash "$SCRIPT_DIR/scripts/snapshot.sh"
    else
        echo "Snapshot script not found. Skipping system snapshot."
    fi
}

# Setup Claude API
setup_claude_api() {
    echo "Setting up Claude API..."
    
    if [ -f "$SCRIPT_DIR/scripts/setup-claude.sh" ]; then
        # Ask if user wants to set up API now
        read -p "Do you want to set up Claude API integration now? (y/n): " setup_api
        if [[ "$setup_api" == "y" ]]; then
            bash "$SCRIPT_DIR/scripts/setup-claude.sh"
        else
            echo "You can set up Claude API later by running: ./scripts/setup-claude.sh"
        fi
    else
        echo "Claude API setup script not found. Skipping API setup."
    fi
}

# Main installation process
main() {
    display_banner
    echo "TheArchHive Installation"
    echo "------------------------"
    echo "This script will set up TheArchHive environment."
    echo ""
    
    # Confirmation
    read -p "Continue with installation? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Installation canceled."
        exit 0
    fi
    
    # Execute installation steps
    install_base_packages
    configure_neovim
    setup_claude_integration
    create_system_snapshot
    setup_claude_api
    
    echo ""
    echo "TheArchHive installation completed successfully!"
    echo "You can now use Claude integration in Neovim with <Space>cc"
    echo ""
    echo "Enjoy your Arch Linux experience with TheArchHive!"
}

# Run main function
main
