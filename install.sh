#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PACKAGES_DIR="$SCRIPT_DIR/packages"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==>${NC} Welcome to TheArchHive installation..."

# Create necessary directories
echo -e "${BLUE}==>${NC} Creating directories..."
mkdir -p "$HOME/.config/nvim/lua"
mkdir -p "$HOME/.TheArchHive/snapshots"

# Install base packages
echo -e "${BLUE}==>${NC} Installing base packages..."
if command -v pacman &> /dev/null; then
    sudo pacman -Syu --needed --noconfirm - < "$PACKAGES_DIR/base.txt"
    
    read -p "Install development packages? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed --noconfirm - < "$PACKAGES_DIR/dev.txt"
    fi
    
    read -p "Install desktop environment packages? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed --noconfirm - < "$PACKAGES_DIR/desktop.txt"
    fi
else
    echo "Pacman not found. Skipping package installation."
    echo "Please install packages manually from the package lists."
fi

# Install Neovim plugin manager
echo -e "${BLUE}==>${NC} Setting up Neovim..."
if [ ! -d "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim" ]; then
    echo "Installing Packer.nvim..."
    git clone --depth 1 https://github.com/wbthomason/packer.nvim \
        "$HOME/.local/share/nvim/site/pack/packer/start/packer.nvim"
fi

# Copy Neovim configuration
echo "Copying Neovim configuration..."
cp -r "$CONFIG_DIR/nvim/"* "$HOME/.config/nvim/"

# Copy Git configuration
echo "Copying Git configuration..."
[ -f "$CONFIG_DIR/git/gitconfig" ] && cp "$CONFIG_DIR/git/gitconfig" "$HOME/.gitconfig"

# Make scripts executable
chmod +x "$SCRIPTS_DIR"/*.sh

# Run setup scripts
"$SCRIPTS_DIR/setup-claude.sh"

# Create initial snapshot
"$SCRIPTS_DIR/snapshot.sh"

echo -e "${GREEN}Installation complete!${NC}"
echo "To start using Claude in Neovim:"
echo "1. Open Neovim: nvim"
echo "2. Install plugins: :PackerSync"
echo "3. Open Claude: <Space>cc"
echo "4. Ask a question and press <Space>ca for a response"
