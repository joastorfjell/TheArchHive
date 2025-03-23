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
    
    # Install Packer
