#!/bin/bash
# TheArchHive Backup Script
# Handles configuration backups using Git

set -e  # Exit on error

# Configuration
CONFIG_DIR="$HOME/.config/thearchhive"
CONFIG_FILE="$CONFIG_DIR/backup_config.json"
DEFAULT_BACKUP_REPO="$HOME/.local/share/thearchhive/backups"

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure required tools are available
check_requirements() {
  if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git is not installed. Please install it first.${NC}"
    exit 1
  fi
  
  if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install it first.${NC}"
    exit 1
  fi
}

# Load configuration
load_config() {
  # Create default config if it doesn't exist
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Configuration file not found. Creating default configuration.${NC}"
    mkdir -p "$CONFIG_DIR"
    
    cat > "$CONFIG_FILE" << EOF
{
  "backup_repo": "$DEFAULT_BACKUP_REPO",
  "git_remote": "",
  "config_files": [
    "~/.config/nvim/init.vim",
    "~/.config/nvim/lua/claude",
    "~/.config/thearchhive",
    "~/.bashrc",
    "~/.zshrc",
    "~/.xinitrc",
    "~/.Xresources"
  ]
}
EOF
  fi
  
  # Verify config file is valid JSON
  if ! jq -e . "$CONFIG_FILE" > /dev/null 2>&1; then
    echo -e "${RED}Error: Invalid configuration file format.${NC}"
    exit 1
  fi
  
  # Load config values
  BACKUP_REPO=$(jq -r '.backup_repo' "$CONFIG_FILE")
  GIT_REMOTE=$(jq -r '.git_remote' "$CONFIG_FILE")
  CONFIG_FILES=$(jq -r '.config_files[]' "$CONFIG_FILE")
  
  # Expand ~ in backup repo path
  BACKUP_REPO="${BACKUP_REPO/#\~/$HOME}"
  
  echo -e "${BLUE}Configuration loaded:${NC}"
  echo -e "  Backup repository: ${BACKUP_REPO}"
  echo -e "  Git remote: ${GIT_REMOTE:-None}"
  echo -e "  Files to backup: $(echo "$CONFIG_FILES" | wc -l)"
}

# Initialize backup repository if it doesn't exist
initialize_repo() {
  if [ ! -d "$BACKUP_REPO" ]; then
    echo -e "${YELLOW}Backup repository doesn't exist. Creating it now.${NC}"
    mkdir -p "$BACKUP_REPO"
    
    # Initialize Git repository
    cd "$BACKUP_REPO"
    git init
    
    # Create initial structure
    mkdir -p config
    
    # Add .gitignore
    cat > .gitignore << EOF
# TheArchHive Backup Repository
# Ignore temporary files
*~
*.swp
*.swo
.DS_Store
EOF
    
    # Initial commit
    git add .gitignore
    git config --local user.name "TheArchHive"
    git config --local user.email "thearchhive@localhost"
    git commit -m "Initialize backup repository"
    
    echo -e "${GREEN}Backup repository initialized successfully.${NC}"
    
    # Set up Git remote if configured
    if [ -n "$GIT_REMOTE" ]; then
      echo -e "${BLUE}Setting up Git remote...${NC}"
      git remote add origin "$GIT_REMOTE"
      echo -e "${GREEN}Git remote configured.${NC}"
    fi
  else
    # Ensure it's a git repository
    if [ ! -d "$BACKUP_REPO/.git" ]; then
      echo -e "${YELLOW}Directory exists but is not a Git repository. Initializing...${NC}"
      cd "$BACKUP_REPO"
      git init
      git config --local user.name "TheArchHive"
      git config --local user.email "thearchhive@localhost"
      
      # Create initial commit if needed
      if [ -z "$(git log -1 --oneline 2>/dev/null)" ]; then
        touch README.md
        echo "# TheArchHive Backup Repository" > README.md
        echo "Created on $(date)" >> README.md
        git add README.md
        git commit -m "Initialize backup repository"
      fi
      
      # Set up Git remote if configured
      if [ -n "$GIT_REMOTE" ]; then
        git remote add origin "$GIT_REMOTE"
      fi
      
      echo -e "${GREEN}Git repository initialized in existing directory.${NC}"
    fi
  fi
}

# Backup configuration files
backup_files() {
  echo -e "${BLUE}Starting backup process...${NC}"
  
  # Initialize backup repository if needed
  initialize_repo
  
  # Change to backup repository
  cd "$BACKUP_REPO"
  
  # Backup each configuration file
  for file in $CONFIG_FILES; do
    # Expand ~ in paths
    expanded_file="${file/#\~/$HOME}"
    
    # Check if file exists
    if [ ! -e "$expanded_file" ]; then
      echo -e "${YELLOW}Warning: $file does not exist, skipping.${NC}"
      continue
    fi
    
    # Determine backup path
    backup_path="$BACKUP_REPO"
    
    # Extract directory name for organization
    if [[ "$file" == ~/.config/* ]]; then
      # For files in ~/.config, keep the structure
      rel_path="${file/#\~\/\.config\//config\/}"
      backup_path="$BACKUP_REPO/$rel_path"
    else
      # For other files, use the basename
      base_name=$(basename "$file")
      backup_path="$BACKUP_REPO/home/$base_name"
    fi
    
    # Create target directory
    mkdir -p "$(dirname "$backup_path")"
    
    # Copy file or directory
    if [ -d "$expanded_file" ]; then
      # It's a directory, ensure the target directory exists
      mkdir -p "$backup_path"
      
      # Rsync to copy only changed files
      rsync -a --delete "$expanded_file/" "$backup_path/"
      echo -e "${GREEN}Backed up directory: $file${NC}"
    else
      # It's a file, copy it
      cp "$expanded_file" "$backup_path"
      echo -e "${GREEN}Backed up file: $file${NC}"
    fi
    
    # Add to git
    git add "$backup_path"
  done
  
  # Commit changes if there are any
  if [ -n "$(git status --porcelain)" ]; then
    git commit -m "Backup: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${GREEN}Committed changes to git repository.${NC}"
    
    # Push to remote if configured
    if [ -n "$GIT_REMOTE" ]; then
      echo -e "${BLUE}Pushing changes to remote...${NC}"
      if git push origin master 2>/dev/null || git push origin main 2>/dev/null; then
        echo -e "${GREEN}Pushed changes to remote repository.${NC}"
      else
        echo -e "${YELLOW}Warning: Failed to push to remote. Check your connection or repository permissions.${NC}"
      fi
    fi
  else
    echo -e "${BLUE}No changes to commit.${NC}"
  fi
}

# Display backup status
show_status() {
  # Check if backup repository exists
  if [ ! -d "$BACKUP_REPO" ]; then
    echo -e "${YELLOW}Backup repository doesn't exist. Run backup to create it.${NC}"
    return
  fi
  
  # Change to backup repository
  cd "$BACKUP_REPO"
  
  # Show git status
  echo -e "${BLUE}Backup repository status:${NC}"
  git status -s
  
  # Show last 5 commits
  echo -e "\n${BLUE}Recent backup history:${NC}"
  git log -5 --oneline
  
  # Check remote status if configured
  if [ -n "$GIT_REMOTE" ]; then
    echo -e "\n${BLUE}Remote repository status:${NC}"
    git remote -v
    
    # Check for unpushed commits
    local_commits=$(git rev-list --count HEAD)
    remote_commits=$(git rev-list --count origin/$(git branch --show-current) 2>/dev/null || echo 0)
    
    if [ "$local_commits" -gt "$remote_commits" ]; then
      echo -e "${YELLOW}You have $(($local_commits - $remote_commits)) unpushed commits.${NC}"
    else
      echo -e "${GREEN}Repository is in sync with remote.${NC}"
    fi
  fi
}

# Restore files from backup
restore_files() {
  local target_dir="$1"
  
  # If no target directory specified, use home directory
  if [ -z "$target_dir" ]; then
    target_dir="$HOME"
  fi
  
  # Check if backup repository exists
  if [ ! -d "$BACKUP_REPO" ]; then
    echo -e "${RED}Error: Backup repository doesn't exist.${NC}"
    exit 1
  fi
  
  echo -e "${BLUE}Restoring configuration files to ${target_dir}...${NC}"
  
  # Process each config file
  for file in $CONFIG_FILES; do
    # Determine backup path
    backup_path=""
    restored_path=""
    
    # Expand ~ in paths
    expanded_file="${file/#\~/$HOME}"
    expanded_file="${expanded_file/#$HOME/$target_dir}"
    
    # Find the backup based on path patterns
    if [[ "$file" == ~/.config/* ]]; then
      # For files in ~/.config
      rel_path="${file/#\~\/\.config\//config\/}"
      backup_path="$BACKUP_REPO/$rel_path"
      restored_path="$expanded_file"
    else
      # For other files in home
      base_name=$(basename "$file")
      backup_path="$BACKUP_REPO/home/$base_name"
      restored_path="$expanded_file"
    fi
    
    # Check if backup exists
    if [ ! -e "$backup_path" ]; then
      echo -e "${YELLOW}Warning: Backup for $file not found, skipping.${NC}"
      continue
    fi
    
    # Create target directory
    mkdir -p "$(dirname "$restored_path")"
    
    # Copy file or directory
    if [ -d "$backup_path" ]; then
      # It's a directory, ensure the target directory exists
      mkdir -p "$restored_path"
      
      # Rsync to copy only changed files
      rsync -a --delete "$backup_path/" "$restored_path/"
      echo -e "${GREEN}Restored directory: $file to $restored_path${NC}"
    else
      # It's a file, copy it
      cp "$backup_path" "$restored_path"
      echo -e "${GREEN}Restored file: $file to $restored_path${NC}"
    fi
  done
  
  echo -e "${GREEN}Restoration complete!${NC}"
}

# Add a file to the backup config
add_file() {
  local file="$1"
  
  if [ -z "$file" ]; then
    echo -e "${RED}Error: No file specified.${NC}"
    exit 1
  fi
  
  # Standardize path with ~
  if [[ "$file" == $HOME* ]]; then
    file="~${file#$HOME}"
  fi
  
  # Check if file is already in the config
  if jq -e ".config_files | index(\"$file\")" "$CONFIG_FILE" > /dev/null; then
    echo -e "${YELLOW}File $file is already in the backup configuration.${NC}"
    return
  fi
  
  # Add file to config
  jq --arg file "$file" '.config_files += [$file]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  
  echo -e "${GREEN}Added $file to backup configuration.${NC}"
  
  # Ask if user wants to backup now
  read -p "Do you want to backup this file now? (y/n) " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    backup_files
  fi
}

# Remove a file from the backup config
remove_file() {
  local file="$1"
  
  if [ -z "$file" ]; then
    echo -e "${RED}Error: No file specified.${NC}"
    exit 1
  fi
  
  # Standardize path with ~
  if [[ "$file" == $HOME* ]]; then
    file="~${file#$HOME}"
  fi
  
  # Check if file is in the config
  if ! jq -e ".config_files | index(\"$file\")" "$CONFIG_FILE" > /dev/null; then
    echo -e "${YELLOW}File $file is not in the backup configuration.${NC}"
    return
  fi
  
  # Remove file from config
  jq --arg file "$file" '.config_files -= [$file]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  
  echo -e "${GREEN}Removed $file from backup configuration.${NC}"
}

# List all files in backup config
list_files() {
  echo -e "${BLUE}Files in backup configuration:${NC}"
  jq -r '.config_files[]' "$CONFIG_FILE" | sort
}

# Set or update git remote
set_remote() {
  local remote="$1"
  
  if [ -z "$remote" ]; then
    echo -e "${RED}Error: No remote URL specified.${NC}"
    exit 1
  fi
  
  # Update config file
  jq --arg remote "$remote" '.git_remote = $remote' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
  mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
  
  # Set remote in git repo if it exists
  if [ -d "$BACKUP_REPO/.git" ]; then
    cd "$BACKUP_REPO"
    
    # Check if remote already exists
    if git remote | grep -q "^origin$"; then
      git remote set-url origin "$remote"
      echo -e "${GREEN}Updated git remote URL.${NC}"
    else
      git remote add origin "$remote"
      echo -e "${GREEN}Added git remote URL.${NC}"
    fi
  fi
  
  echo -e "${GREEN}Git remote set to: $remote${NC}"
}

# Main function
main() {
  # Check requirements
  check_requirements
  
  # Load configuration
  load_config
  
  # Process command
  command="$1"
  
  case "$command" in
    backup|b)
      backup_files
      ;;
    status|s)
      show_status
      ;;
    restore|r)
      restore_files "$2"
      ;;
    add|a)
      add_file "$2"
      ;;
    remove|rm)
      remove_file "$2"
      ;;
    list|l)
      list_files
      ;;
    remote)
      set_remote "$2"
      ;;
    help|h|*)
      echo "Usage: $0 <command> [options]"
      echo
      echo "Commands:"
      echo "  backup, b             Backup all configured files"
      echo "  status, s             Show backup repository status"
      echo "  restore, r [target]   Restore files (optionally to target directory)"
      echo "  add, a <file>         Add a file to backup configuration"
      echo "  remove, rm <file>     Remove a file from backup configuration"
      echo "  list, l               List all files in backup configuration"
      echo "  remote <url>          Set or update git remote URL"
      echo "  help, h               Show this help message"
      ;;
  esac
}

# Run main function
main "$@"
