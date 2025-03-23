#!/usr/bin/env python3

"""
TheArchHive Standard Operating Tools

This module provides standardized tools for Claude to use across all instances
in TheArchHive network. These tools handle common tasks like package management,
configuration updates, and system optimization.
"""

import os
import sys
import json
import time
import shutil
import logging
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.expanduser("~/.local/share/thearchhive/tools.log")),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("thearchhive-tools")

# Configuration paths
CONFIG_DIR = os.path.expanduser("~/.config/thearchhive")
SCRIPT_DIR = os.path.join(CONFIG_DIR, "scripts")
BACKUP_SCRIPT = os.path.join(SCRIPT_DIR, "backup.sh")
CLAUDESCRIPT_PATH = os.path.join(SCRIPT_DIR, "claudescript.py")

# Ensure paths exist
os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(SCRIPT_DIR, exist_ok=True)

class PackageManager:
    """Package management tools for Arch Linux"""
    
    @staticmethod
    def is_installed(package_name: str) -> bool:
        """Check if a package is installed"""
        try:
            result = subprocess.run(
                ["pacman", "-Qi", package_name], 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                text=True
            )
            return result.returncode == 0
        except Exception as e:
            logger.error(f"Error checking if {package_name} is installed: {e}")
            return False
    
    @staticmethod
    def list_installed() -> List[Dict[str, str]]:
        """List all explicitly installed packages"""
        try:
            result = subprocess.run(
                ["pacman", "-Qe"], 
                stdout=subprocess.PIPE, 
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error listing installed packages: {result.stderr}")
                return []
            
            packages = []
            for line in result.stdout.splitlines():
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        packages.append({
                            "name": parts[0],
                            "version": parts[1]
                        })
            
            return packages
        except Exception as e:
            logger.error(f"Error listing installed packages: {e}")
            return []
    
    @staticmethod
    def install(package_name: str, noconfirm: bool = False) -> bool:
        """Install a package"""
        try:
            cmd = ["sudo", "pacman", "-S", package_name]
            if noconfirm:
                cmd.append("--noconfirm")
            
            logger.info(f"Installing package: {package_name}")
            result = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error installing {package_name}: {result.stderr}")
                return False
            
            logger.info(f"Successfully installed {package_name}")
            return True
        except Exception as e:
            logger.error(f"Error installing {package_name}: {e}")
            return False
    
    @staticmethod
    def remove(package_name: str, noconfirm: bool = False) -> bool:
        """Remove a package"""
        try:
            cmd = ["sudo", "pacman", "-R", package_name]
            if noconfirm:
                cmd.append("--noconfirm")
            
            logger.info(f"Removing package: {package_name}")
            result = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error removing {package_name}: {result.stderr}")
                return False
            
            logger.info(f"Successfully removed {package_name}")
            return True
        except Exception as e:
            logger.error(f"Error removing {package_name}: {e}")
            return False
    
    @staticmethod
    def update_system(noconfirm: bool = False) -> bool:
        """Update the system"""
        try:
            cmd = ["sudo", "pacman", "-Syu"]
            if noconfirm:
                cmd.append("--noconfirm")
            
            logger.info("Updating system...")
            result = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error updating system: {result.stderr}")
                return False
            
            logger.info("Successfully updated system")
            return True
        except Exception as e:
            logger.error(f"Error updating system: {e}")
            return False
    
    @staticmethod
    def search(search_term: str) -> List[Dict[str, str]]:
        """Search for packages"""
        try:
            result = subprocess.run(
                ["pacman", "-Ss", search_term],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error searching for {search_term}: {result.stderr}")
                return []
            
            packages = []
            current_pkg = None
            
            for line in result.stdout.splitlines():
                if line.startswith(" "):
                    # This is a description line
                    if current_pkg:
                        current_pkg["description"] = line.strip()
                        packages.append(current_pkg)
                        current_pkg = None
                else:
                    # This is a package line
                    parts = line.split("/", 1)
                    if len(parts) == 2:
                        repo = parts[0]
                        pkg_info = parts[1].split(" ", 1)
                        if len(pkg_info) == 2:
                            name_version = pkg_info[0]
                            name_parts = name_version.split("-")
                            if len(name_parts) >= 2:
                                name = "-".join(name_parts[:-1])
                                version = name_parts[-1]
                                current_pkg = {
                                    "repository": repo,
                                    "name": name,
                                    "version": version
                                }
            
            return packages
        except Exception as e:
            logger.error(f"Error searching for {search_term}: {e}")
            return []

class ConfigManager:
    """Configuration file management tools"""
    
    @staticmethod
    def backup_configs() -> bool:
        """Backup all configuration files"""
        try:
            if not os.path.exists(BACKUP_SCRIPT):
                logger.error(f"Backup script not found at {BACKUP_SCRIPT}")
                return False
            
            logger.info("Backing up configuration files...")
            result = subprocess.run(
                [BACKUP_SCRIPT],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error backing up configs: {result.stderr}")
                return False
            
            logger.info("Successfully backed up configuration files")
            return True
        except Exception as e:
            logger.error(f"Error backing up configs: {e}")
            return False
    
    @staticmethod
    def update_config_file(file_path: str, updates: Dict[str, str], 
                          create_if_missing: bool = False,
                          backup: bool = True) -> bool:
        """
        Update a configuration file with key-value pairs
        For simple configuration files with key=value format
        """
        try:
            file_path = os.path.expanduser(file_path)
            
            # Create backup
            if backup and os.path.exists(file_path):
                backup_path = f"{file_path}.bak.{int(time.time())}"
                shutil.copy2(file_path, backup_path)
                logger.info(f"Created backup of {file_path} at {backup_path}")
            
            # Read existing content
            content = []
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    content = f.readlines()
            elif not create_if_missing:
                logger.error(f"File {file_path} does not exist and create_if_missing is False")
                return False
            
            # Process updates
            updated = False
            for key, value in updates.items():
                key_updated = False
                
                # Update existing key
                for i, line in enumerate(content):
                    if line.strip().startswith(f"{key}=") or line.strip().startswith(f"{key} ="):
                        content[i] = f"{key}={value}\n"
                        key_updated = True
                        updated = True
                        break
                
                # Add new key if it doesn't exist
                if not key_updated:
                    content.append(f"{key}={value}\n")
                    updated = True
            
            # Write back to file
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, 'w') as f:
                f.writelines(content)
            
            logger.info(f"Updated configuration file {file_path}")
            return True
        except Exception as e:
            logger.error(f"Error updating config file {file_path}: {e}")
            return False
    
    @staticmethod
    def add_to_config_file(file_path: str, content: str, 
                          create_if_missing: bool = True,
                          backup: bool = True) -> bool:
        """Add content to the end of a configuration file"""
        try:
            file_path = os.path.expanduser(file_path)
            
            # Create backup
            if backup and os.path.exists(file_path):
                backup_path = f"{file_path}.bak.{int(time.time())}"
                shutil.copy2(file_path, backup_path)
                logger.info(f"Created backup of {file_path} at {backup_path}")
            
            # Create directory if needed
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            
            # Append to file
            with open(file_path, 'a+') as f:
                f.write(f"\n{content}\n")
            
            logger.info(f"Added content to {file_path}")
            return True
        except Exception as e:
            logger.error(f"Error adding to config file {file_path}: {e}")
            return False
    
    @staticmethod
    def update_json_config(file_path: str, updates: Dict[str, Any],
                          create_if_missing: bool = True,
                          backup: bool = True) -> bool:
        """Update a JSON configuration file"""
        try:
            file_path = os.path.expanduser(file_path)
            
            # Create backup
            if backup and os.path.exists(file_path):
                backup_path = f"{file_path}.bak.{int(time.time())}"
                shutil.copy2(file_path, backup_path)
                logger.info(f"Created backup of {file_path} at {backup_path}")
            
            # Read existing content
            config = {}
            if os.path.exists(file_path):
                with open(file_path, 'r') as f:
                    config = json.load(f)
            elif not create_if_missing:
                logger.error(f"File {file_path} does not exist and create_if_missing is False")
                return False
            
            # Update config
            config.update(updates)
            
            # Write back to file
            os.makedirs(os.path.dirname(file_path), exist_ok=True)
            with open(file_path, 'w') as f:
                json.dump(config, f, indent=2)
            
            logger.info(f"Updated JSON config file {file_path}")
            return True
        except Exception as e:
            logger.error(f"Error updating JSON config file {file_path}: {e}")
            return False

class SystemOptimizer:
    """System optimization tools"""
    
    @staticmethod
    def apply_sysctl_setting(setting: str, value: str) -> bool:
        """Apply a sysctl setting"""
        try:
            logger.info(f"Setting sysctl {setting}={value}")
            
            # Backup current settings
            ConfigManager.backup_configs()
            
            # Apply setting immediately
            result = subprocess.run(
                ["sudo", "sysctl", "-w", f"{setting}={value}"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error applying sysctl setting: {result.stderr}")
                return False
            
            # Make setting persistent
            sysctl_file = "/etc/sysctl.d/99-thearchhive.conf"
            updates = {setting: value}
            
            result = ConfigManager.update_config_file(
                sysctl_file,
                updates,
                create_if_missing=True,
                backup=True
            )
            
            if not result:
                logger.error(f"Failed to make sysctl setting persistent")
                return False
            
            logger.info(f"Successfully applied sysctl setting {setting}={value}")
            return True
        except Exception as e:
            logger.error(f"Error applying sysctl setting: {e}")
            return False
    
    @staticmethod
    def optimize_pacman() -> bool:
        """Optimize pacman configuration"""
        try:
            pacman_conf = "/etc/pacman.conf"
            
            # Backup current config
            ConfigManager.backup_configs()
            
            # Read current config
            with open(pacman_conf, 'r') as f:
                content = f.read()
            
            # Check for parallel downloads
            if "ParallelDownloads" not in content:
                logger.info("Enabling parallel downloads in pacman")
                
                # Find the [options] section
                if "[options]" in content:
                    content = content.replace(
                        "[options]",
                        "[options]\nParallelDownloads = 5"
                    )
                    
                    # Write updated config
                    with open("/tmp/pacman.conf.new", 'w') as f:
                        f.write(content)
                    
                    # Apply changes with sudo
                    result = subprocess.run(
                        ["sudo", "mv", "/tmp/pacman.conf.new", pacman_conf],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True
                    )
                    
                    if result.returncode != 0:
                        logger.error(f"Error updating pacman.conf: {result.stderr}")
                        return False
            
            logger.info("Successfully optimized pacman configuration")
            return True
        except Exception as e:
            logger.error(f"Error optimizing pacman: {e}")
            return False
    
    @staticmethod
    def configure_neovim_performance() -> bool:
        """Configure Neovim for better performance"""
        try:
            nvim_config = os.path.expanduser("~/.config/nvim/init.vim")
            
            # Create directory if needed
            os.makedirs(os.path.dirname(nvim_config), exist_ok=True)
            
            # Performance optimizations to add
            optimizations = """
" TheArchHive Neovim Performance Optimizations
set lazyredraw
set nobackup
set nowritebackup
set noswapfile
set hidden
set history=100
set updatetime=300
set timeoutlen=500
"""
            
            result = ConfigManager.add_to_config_file(
                nvim_config,
                optimizations,
                create_if_missing=True,
                backup=True
            )
            
            if not result:
                logger.error("Failed to optimize Neovim configuration")
                return False
            
            logger.info("Successfully optimized Neovim configuration")
            return True
        except Exception as e:
            logger.error(f"Error optimizing Neovim: {e}")
            return False
    
    @staticmethod
    def configure_zsh_performance() -> bool:
        """Configure Zsh for better performance"""
        try:
            zshrc = os.path.expanduser("~/.zshrc")
            
            # Optimizations to add
            optimizations = """
# TheArchHive Zsh Performance Optimizations
zstyle ':completion:*' cache-path ~/.cache/zsh/cache
zstyle ':completion:*' use-cache on
HISTSIZE=1000
SAVEHIST=1000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_SAVE_NO_DUPS
"""
            
            result = ConfigManager.add_to_config_file(
                zshrc,
                optimizations,
                create_if_missing=True,
                backup=True
            )
            
            if not result:
                logger.error("Failed to optimize Zsh configuration")
                return False
            
            logger.info("Successfully optimized Zsh configuration")
            return True
        except Exception as e:
            logger.error(f"Error optimizing Zsh: {e}")
            return False

class NvimTools:
    """Neovim-specific tools"""
    
    @staticmethod
    def install_plugin(plugin_url: str, plugin_name: str = None) -> bool:
        """Install a Neovim plugin"""
        try:
            # Determine plugin name from URL if not provided
            if not plugin_name:
                plugin_name = os.path.basename(plugin_url).replace(".git", "")
            
            # Plugin path
            plugin_dir = os.path.expanduser(f"~/.config/nvim/pack/plugins/start/{plugin_name}")
            
            # Check if already installed
            if os.path.exists(plugin_dir):
                logger.info(f"Plugin {plugin_name} is already installed")
                return True
            
            # Create plugin directory
            os.makedirs(os.path.dirname(plugin_dir), exist_ok=True)
            
            # Clone plugin repository
            logger.info(f"Installing Neovim plugin: {plugin_name}")
            result = subprocess.run(
                ["git", "clone", plugin_url, plugin_dir],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Error installing plugin {plugin_name}: {result.stderr}")
                return False
            
            logger.info(f"Successfully installed Neovim plugin: {plugin_name}")
            return True
        except Exception as e:
            logger.error(f"Error installing Neovim plugin: {e}")
            return False
    
    @staticmethod
    def setup_basic_plugins() -> bool:
        """Set up basic Neovim plugins"""
        plugins = [
            {"url": "https://github.com/nvim-lua/plenary.nvim.git", "name": "plenary.nvim"},
            {"url": "https://github.com/nvim-telescope/telescope.nvim.git", "name": "telescope.nvim"},
            {"url": "https://github.com/neovim/nvim-lspconfig.git", "name": "nvim-lspconfig"}
        ]
        
        success = True
        for plugin in plugins:
            if not NvimTools.install_plugin(plugin["url"], plugin["name"]):
                success = False
        
        return success

class ClaudeScriptRunner:
    """Tools for working with ClaudeScript"""
    
    @staticmethod
    def create_snapshot() -> Optional[str]:
        """
        Create a system snapshot using ClaudeScript
        
        Returns:
            Path to the snapshot file, or None if failed
        """
        try:
            snapshot_dir = os.path.expanduser("~/.local/share/thearchhive/snapshots")
            os.makedirs(snapshot_dir, exist_ok=True)
            
            timestamp = int(time.time())
            snapshot_path = os.path.join(snapshot_dir, f"snapshot_{timestamp}.txt")
            
            logger.info(f"Creating system snapshot at {snapshot_path}")
            
            if os.path.exists(CLAUDESCRIPT_PATH):
                result = subprocess.run(
                    ["python", CLAUDESCRIPT_PATH, "snapshot", "--output", snapshot_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )
                
                if result.returncode != 0:
                    logger.error(f"Error creating snapshot: {result.stderr}")
                    return None
                
                logger.info(f"Successfully created snapshot at {snapshot_path}")
                return snapshot_path
            else:
                logger.error(f"ClaudeScript not found at {CLAUDESCRIPT_PATH}")
                return None
        except Exception as e:
            logger.error(f"Error creating snapshot: {e}")
            return None
    
    @staticmethod
    def apply_claudescript(script: str) -> bool:
        """
        Apply a ClaudeScript command
        
        Args:
            script: The ClaudeScript command to apply
            
        Returns:
            True if successful, False otherwise
        """
        try:
            logger.info(f"Applying ClaudeScript: {script}")
            
            # Check script format
            if script.startswith("p:"):
                # Package installation
                package = script[2:]
                return PackageManager.install(package)
            elif script.startswith("cmd:"):
                # Command execution
                command = script[4:]
                result = subprocess.run(
                    command,
                    shell=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )
                
                if result.returncode != 0:
                    logger.error(f"Error executing command: {result.stderr}")
                    return False
                
                logger.info(f"Command executed successfully")
                return True
            elif script.startswith("r:"):
                # Runtime configuration
                config = script[2:]
                # Parse format application:setting
                if ":" in config:
                    app, setting = config.split(":", 1)
                    if app == "neovim" or app == "nvim":
                        nvim_config = os.path.expanduser("~/.config/nvim/init.vim")
                        return ConfigManager.add_to_config_file(nvim_config, setting)
                    elif app == "zsh":
                        zshrc = os.path.expanduser("~/.zshrc")
                        return ConfigManager.add_to_config_file(zshrc, setting)
                    elif app == "bash":
                        bashrc = os.path.expanduser("~/.bashrc")
                        return ConfigManager.add_to_config_file(bashrc, setting)
                    else:
                        logger.error(f"Unknown application: {app}")
                        return False
                else:
                    logger.error(f"Invalid runtime configuration format: {config}")
                    return False
            elif script.startswith("t:"):
                # System tweak
                tweak = script[2:]
                # Parse format component:tweak
                if ":" in tweak:
                    component, setting = tweak.split(":", 1)
                    if component == "sysctl":
                        # Format: key=value
                        if "=" in setting:
                            key, value = setting.split("=", 1)
                            return SystemOptimizer.apply_sysctl_setting(key.strip(), value.strip())
                        else:
                            logger.error(f"Invalid sysctl format: {setting}")
                            return False
                    else:
                        logger.error(f"Unknown tweak component: {component}")
                        return False
                else:
                    logger.error(f"Invalid tweak format: {tweak}")
                    return False
            else:
                logger.error(f"Unsupported ClaudeScript command: {script}")
                return False
        except Exception as e:
            logger.error(f"Error applying ClaudeScript: {e}")
            return False
    
    @staticmethod
    def apply_claudescript_file(file_path: str) -> bool:
        """
        Apply ClaudeScript commands from a file
        
        Args:
            file_path: Path to the file containing ClaudeScript commands
            
        Returns:
            True if all commands were successful, False otherwise
        """
        try:
            file_path = os.path.expanduser(file_path)
            
            if not os.path.exists(file_path):
                logger.error(f"ClaudeScript file not found: {file_path}")
                return False
            
            logger.info(f"Applying ClaudeScript from file: {file_path}")
            
            with open(file_path, 'r') as f:
                lines = f.readlines()
            
            success = True
            for line in lines:
                line = line.strip()
                if line and not line.startswith("#"):
                    if not ClaudeScriptRunner.apply_claudescript(line):
                        success = False
            
            return success
        except Exception as e:
            logger.error(f"Error applying ClaudeScript from file: {e}")
            return False


    @staticmethod
    def validate_script(script_content, validation_level="normal"):
        """
        Validate a script using the MCP server
    
        Args:
            script_content: The content of the script to validate
            validation_level: Level of validation (minimal, normal, strict)
        
        Returns:
            Dictionary with validation information including ID and script path
        """
        try:
            # Check if MCP server is running
            mcp_url = "http://127.0.0.1:5678"  # Should be configurable
        
            # Send script for validation
            response = requests.post(
                f"{mcp_url}/script/validate",
                json={
                    "script": script_content,
                    "validation_level": validation_level
                }
            )
        
            if response.status_code != 200:
                logger.error(f"Error validating script: {response.text}")
                return None
        
            return response.json()
        except Exception as e:
            logger.error(f"Error validating script: {e}")
            return None

    @staticmethod
    def get_validation_results(validation_id):
        """
        Get the results of a validated script
    
        Args:
            validation_id: The validation ID returned from validate_script
        
        Returns:
            Dictionary with validation results
        """
        try:
            # Check if MCP server is running
            mcp_url = "http://127.0.0.1:5678"  # Should be configurable
        
            # Get validation results
            response = requests.get(f"{mcp_url}/script/results/{validation_id}")
        
            if response.status_code != 200:
                logger.error(f"Error getting validation results: {response.text}")
                return None
        
            return response.json()
        except Exception as e:
            logger.error(f"Error getting validation results: {e}")
            return None

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="TheArchHive Standard Operating Tools")
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # Package commands
    pkg_parser = subparsers.add_parser("package", help="Package management commands")
    pkg_subparsers = pkg_parser.add_subparsers(dest="subcommand", help="Package subcommand")
    
    # package install
    pkg_install = pkg_subparsers.add_parser("install", help="Install a package")
    pkg_install.add_argument("package", help="Package name")
    pkg_install.add_argument("--noconfirm", action="store_true", help="Don't ask for confirmation")
    
    # package remove
    pkg_remove = pkg_subparsers.add_parser("remove", help="Remove a package")
    pkg_remove.add_argument("package", help="Package name")
    pkg_remove.add_argument("--noconfirm", action="store_true", help="Don't ask for confirmation")
    
    # package list
    pkg_subparsers.add_parser("list", help="List installed packages")
    
    # package search
    pkg_search = pkg_subparsers.add_parser("search", help="Search for packages")
    pkg_search.add_argument("term", help="Search term")
    
    # package update
    pkg_update = pkg_subparsers.add_parser("update", help="Update the system")
    pkg_update.add_argument("--noconfirm", action="store_true", help="Don't ask for confirmation")
    
    # Config commands
    config_parser = subparsers.add_parser("config", help="Configuration management commands")
    config_subparsers = config_parser.add_subparsers(dest="subcommand", help="Config subcommand")
    
    # config backup
    config_subparsers.add_parser("backup", help="Backup configuration files")
    
    # config update
    config_update = config_subparsers.add_parser("update", help="Update a configuration file")
    config_update.add_argument("file", help="Configuration file path")
    config_update.add_argument("--key", required=True, help="Configuration key")
    config_update.add_argument("--value", required=True, help="Configuration value")
    config_update.add_argument("--create", action="store_true", help="Create file if it doesn't exist")
    
    # config add
    config_add = config_subparsers.add_parser("add", help="Add content to a configuration file")
    config_add.add_argument("file", help="Configuration file path")
    config_add.add_argument("--content", required=True, help="Content to add")
    
    # Optimize commands
    optimize_parser = subparsers.add_parser("optimize", help="System optimization commands")
    optimize_subparsers = optimize_parser.add_subparsers(dest="subcommand", help="Optimize subcommand")
    
    # optimize sysctl
    optimize_sysctl = optimize_subparsers.add_parser("sysctl", help="Apply sysctl setting")
    optimize_sysctl.add_argument("--key", required=True, help="Sysctl key")
    optimize_sysctl.add_argument("--value", required=True, help="Sysctl value")
    
    # optimize pacman
    optimize_subparsers.add_parser("pacman", help="Optimize pacman configuration")
    
    # optimize nvim
    optimize_subparsers.add_parser("nvim", help="Optimize Neovim configuration")
    
    # optimize zsh
    optimize_subparsers.add_parser("zsh", help="Optimize Zsh configuration")
    
    # nvim commands
    nvim_parser = subparsers.add_parser("nvim", help="Neovim tools")
    nvim_subparsers = nvim_parser.add_subparsers(dest="subcommand", help="Neovim subcommand")
    
    # nvim install-plugin
    nvim_install = nvim_subparsers.add_parser("install-plugin", help="Install a Neovim plugin")
    nvim_install.add_argument("--url", required=True, help="Plugin repository URL")
    nvim_install.add_argument("--name", help="Plugin name (default: derived from URL)")
    
    # nvim setup-basic
    nvim_subparsers.add_parser("setup-basic", help="Set up basic Neovim plugins")
    
    # claudescript commands
    cs_parser = subparsers.add_parser("claudescript", help="ClaudeScript tools")
    cs_subparsers = cs_parser.add_subparsers(dest="subcommand", help="ClaudeScript subcommand")
    
    # claudescript snapshot
    cs_subparsers.add_parser("snapshot", help="Create a system snapshot")
    
    # claudescript apply
    cs_apply = cs_subparsers.add_parser("apply", help="Apply a ClaudeScript command")
    cs_apply.add_argument("script", help="ClaudeScript command")
    
    # claudescript apply-file
    cs_apply_file = cs_subparsers.add_parser("apply-file", help="Apply ClaudeScript commands from a file")
    cs_apply_file.add_argument("file", help="File path")
    
    return parser.parse_args()

def main():
    """Main function"""
    args = parse_arguments()
    
    if args.command == "package":
        if args.subcommand == "install":
            success = PackageManager.install(args.package, args.noconfirm)
            sys.exit(0 if success else 1)
        elif args.subcommand == "remove":
            success = PackageManager.remove(args.package, args.noconfirm)
            sys.exit(0 if success else 1)
        elif args.subcommand == "list":
            packages = PackageManager.list_installed()
            for pkg in packages:
                print(f"{pkg['name']} {pkg['version']}")
            sys.exit(0)
        elif args.subcommand == "search":
            packages = PackageManager.search(args.term)
            for pkg in packages:
                print(f"{pkg.get('repository', 'unknown')}/{pkg.get('name', 'unknown')} {pkg.get('version', 'unknown')}")
                if 'description' in pkg:
                    print(f"    {pkg['description']}")
            sys.exit(0)
        elif args.subcommand == "update":
            success = PackageManager.update_system(args.noconfirm)
            sys.exit(0 if success else 1)
    elif args.command == "config":
        if args.subcommand == "backup":
            success = ConfigManager.backup_configs()
            sys.exit(0 if success else 1)
        elif args.subcommand == "update":
            success = ConfigManager.update_config_file(args.file, {args.key: args.value}, args.create)
            sys.exit(0 if success else 1)
        elif args.subcommand == "add":
            success = ConfigManager.add_to_config_file(args.file, args.content)
            sys.exit(0 if success else 1)
    elif args.command == "optimize":
        if args.subcommand == "sysctl":
            success = SystemOptimizer.apply_sysctl_setting(args.key, args.value)
            sys.exit(0 if success else 1)
        elif args.subcommand == "pacman":
            success = SystemOptimizer.optimize_pacman()
            sys.exit(0 if success else 1)
        elif args.subcommand == "nvim":
            success = SystemOptimizer.configure_neovim_performance()
            sys.exit(0 if success else 1)
        elif args.subcommand == "zsh":
            success = SystemOptimizer.configure_zsh_performance()
            sys.exit(0 if success else 1)
    elif args.command == "nvim":
        if args.subcommand == "install-plugin":
            success = NvimTools.install_plugin(args.url, args.name)
            sys.exit(0 if success else 1)
        elif args.subcommand == "setup-basic":
            success = NvimTools.setup_basic_plugins()
            sys.exit(0 if success else 1)
    elif args.command == "claudescript":
        if args.subcommand == "snapshot":
            snapshot_path = ClaudeScriptRunner.create_snapshot()
            if snapshot_path:
                print(f"Snapshot created: {snapshot_path}")
                sys.exit(0)
            else:
                sys.exit(1)
        elif args.subcommand == "apply":
            success = ClaudeScriptRunner.apply_claudescript(args.script)
            sys.exit(0 if success else 1)
        elif args.subcommand == "apply-file":
            success = ClaudeScriptRunner.apply_claudescript_file(args.file)
            sys.exit(0 if success else 1)
    else:
        print("No command specified. Use --help for usage information.")
        sys.exit(1)

if __name__ == "__main__":
    main()
