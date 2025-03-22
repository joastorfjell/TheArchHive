#!/bin/bash

# Define the repository directory
REPO_DIR="$HOME/TheArchHive"

# Ensure we're in the repo directory
cd "$REPO_DIR" || { echo "Error: Repository directory not found"; exit 1; }

# Backup Neovim configs
echo "Backing up Neovim configuration..."
mkdir -p "$REPO_DIR/config/nvim/lua"
cp -r "$HOME/.config/nvim/init.vim" "$REPO_DIR/config/nvim/" 2>/dev/null || echo "init.vim not found"
cp -r "$HOME/.config/nvim/lua/"* "$REPO_DIR/config/nvim/lua/" 2>/dev/null || echo "No Lua files found"

# Backup Git config
echo "Backing up Git configuration..."
mkdir -p "$REPO_DIR/config/git"
cp "$HOME/.gitconfig" "$REPO_DIR/config/git/gitconfig" 2>/dev/null || echo "gitconfig not found"

# Create latest snapshot
echo "Creating system snapshot..."
"$REPO_DIR/scripts/snapshot.sh"

# Save latest snapshot to repo
cp "$HOME/.TheArchHive/latest_snapshot.txt" "$REPO_DIR/docs/latest_snapshot.txt" 2>/dev/null || echo "No snapshot found"

# Commit changes
echo "Committing changes to the repository..."
git add .
git commit -m "Automatic backup: $(date '+%Y-%m-%d %H:%M:%S')" || echo "No changes to commit"

# Ask to push changes
read -p "Push changes to remote repository? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push
fi

echo "Backup completed successfully!"
