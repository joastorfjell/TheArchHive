#!/bin/bash
# TheArchHive Configuration Backup System
# ~/.config/thearchhive/scripts/backup.sh

set -e

# Default configuration
BACKUP_REPO="$HOME/.local/share/thearchhive/backups"
CONFIG_DIR="$HOME/.config"
LOG_FILE="$BACKUP_REPO/backup.log"
GIT_REMOTE=""

# Configuration files to track
CONFIG_FILES=(
  "$HOME/.config/nvim/init.vim"
  "$HOME/.config/nvim/lua/claude"
  "$HOME/.config/thearchhive"
  "$HOME/.bashrc"
  "$HOME/.zshrc"
  "$HOME/.xinitrc"
  "$HOME/.Xresources"
)

# Ensure backup repo exists
setup_repo() {
  if [ ! -d "$BACKUP_REPO" ]; then
    mkdir -p "$BACKUP_REPO"
    cd "$BACKUP_REPO"
    git init
    echo "# TheArchHive Configuration Backup" > README.md
    git add README.md
    git config user.name "TheArchHive"
    git config user.email "thearchhive@localhost"
    git commit -m "Initial commit"
    echo "Created backup repository at $BACKUP_REPO"
  fi
}

# Load configuration
load_config() {
  CONFIG_FILE="$HOME/.config/thearchhive/backup_config.json"
  if [ -f "$CONFIG_FILE" ]; then
    if command -v jq &> /dev/null; then
      BACKUP_REPO=$(jq -r '.backup_repo // "'"$BACKUP_REPO"'"' "$CONFIG_FILE")
      GIT_REMOTE=$(jq -r '.git_remote // ""' "$CONFIG_FILE")
      
      # Parse config files array if it exists
      if jq -e '.config_files' "$CONFIG_FILE" &> /dev/null; then
        readarray -t CONFIG_FILES < <(jq -r '.config_files[]' "$CONFIG_FILE")
      fi
    else
      echo "Warning: jq not installed, using default configuration"
    fi
  fi
}

# Create default configuration if it doesn't exist
create_default_config() {
  CONFIG_DIR="$HOME/.config/thearchhive"
  CONFIG_FILE="$CONFIG_DIR/backup_config.json"
  
  if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
  fi
  
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << EOF
{
  "backup_repo": "$HOME/.local/share/thearchhive/backups",
  "git_remote": "",
  "config_files": [
    "$HOME/.config/nvim/init.vim",
    "$HOME/.config/nvim/lua/claude",
    "$HOME/.config/thearchhive",
    "$HOME/.bashrc",
    "$HOME/.zshrc",
    "$HOME/.xinitrc",
    "$HOME/.Xresources"
  ]
}
EOF
    echo "Created default backup configuration at $CONFIG_FILE"
  fi
}

# Log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Backup a single file
backup_file() {
  local src="$1"
  local filename=$(basename "$src")
  local target_dir="$BACKUP_REPO/$(dirname "$src" | sed "s|^$HOME|home|")"
  local target="$target_dir/$filename"
  
  # Skip if source doesn't exist
  if [ ! -e "$src" ]; then
    log "Skipping $src - file does not exist"
    return
  fi
  
  # Create target directory if needed
  mkdir -p "$target_dir"
  
  # Copy file or directory
  if [ -d "$src" ]; then
    rsync -a --delete "$src/" "$target/"
    log "Backed up directory $src"
  else
    cp "$src" "$target"
    log "Backed up file $src"
  fi
  
  # Add to git
  cd "$BACKUP_REPO"
  git add "$target" || log "Failed to add $target to git"
}

# Commit changes
commit_changes() {
  cd "$BACKUP_REPO"
  if git diff --staged --quiet; then
    log "No changes to commit"
    return
  fi
  
  # Get system info for commit message
  KERNEL=$(uname -r)
  HOSTNAME=$(hostname)
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  
  # Commit changes
  git commit -m "Backup from $HOSTNAME on $TIMESTAMP (kernel: $KERNEL)"
  log "Committed changes to backup repository"
  
  # Push to remote if configured
  if [ -n "$GIT_REMOTE" ]; then
    if ! git remote | grep -q "^origin$"; then
      git remote add origin "$GIT_REMOTE"
    fi
    git push origin master || log "Failed to push to remote"
  fi
}

# Display backup status
display_status() {
  cd "$BACKUP_REPO"
  echo "================ TheArchHive Backup Status ================"
  echo "Backup repository: $BACKUP_REPO"
  echo "Last backup: $(git log -1 --format="%cd" --date=local)"
  echo "Total backups: $(git rev-list --count HEAD)"
  
  if [ -n "$GIT_REMOTE" ]; then
    echo "Remote repository: $GIT_REMOTE"
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "not configured")
    
    if [ "$LOCAL" = "$REMOTE" ]; then
      echo "Remote status: In sync"
    else
      echo "Remote status: Not in sync"
    fi
  else
    echo "Remote repository: Not configured"
  fi
  
  echo "Tracked configuration files:"
  for file in "${CONFIG_FILES[@]}"; do
    if [ -e "$file" ]; then
      echo "  ✓ $file"
    else
      echo "  ✗ $file (missing)"
    fi
  done
  echo "=========================================================="
}

# Main function
main() {
  # Create default config if it doesn't exist
  create_default_config
  
  # Load configuration
  load_config
  
  # Ensure log directory exists
  mkdir -p "$(dirname "$LOG_FILE")"
  
  # Setup repository
  setup_repo
  
  # Process command line arguments
  case "$1" in
    status)
      display_status
      ;;
    add)
      if [ -z "$2" ]; then
        echo "Usage: backup.sh add <file_or_directory>"
        exit 1
      fi
      
      # Add file to configuration
      FILE_TO_ADD=$(realpath "$2")
      CONFIG_FILE="$HOME/.config/thearchhive/backup_config.json"
      
      if command -v jq &> /dev/null; then
        NEW_CONFIG=$(jq ".config_files += [\"$FILE_TO_ADD\"]" "$CONFIG_FILE")
        echo "$NEW_CONFIG" > "$CONFIG_FILE"
        echo "Added $FILE_TO_ADD to tracked files"
        
        # Reload config and backup the new file
        load_config
        backup_file "$FILE_TO_ADD"
        commit_changes
      else
        echo "Error: jq not installed, can't modify configuration"
        exit 1
      fi
      ;;
    setup-remote)
      if [ -z "$2" ]; then
        echo "Usage: backup.sh setup-remote <git_remote_url>"
        exit 1
      fi
      
      # Set git remote
      CONFIG_FILE="$HOME/.config/thearchhive/backup_config.json"
      
      if command -v jq &> /dev/null; then
        NEW_CONFIG=$(jq ".git_remote = \"$2\"" "$CONFIG_FILE")
        echo "$NEW_CONFIG" > "$CONFIG_FILE"
        
        # Set up git remote
        cd "$BACKUP_REPO"
        if git remote | grep -q "^origin$"; then
          git remote set-url origin "$2"
        else
          git remote add origin "$2"
        fi
        
        echo "Set remote repository to $2"
      else
        echo "Error: jq not installed, can't modify configuration"
        exit 1
      fi
      ;;
    *)
      # Default action: backup files
      log "Starting backup"
      
      for file in "${CONFIG_FILES[@]}"; do
        backup_file "$file"
      done
      
      commit_changes
      log "Backup completed"
      ;;
  esac
}

# Run main function
main "$@"
