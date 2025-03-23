#!/usr/bin/env python3

"""
MCP (Model Context Protocol) Server for TheArchHive
Provides system information to Claude for better decision-making
"""

import os
import json
import psutil
import platform
import subprocess
from flask import Flask, jsonify, request
import logging
import sys
from pathlib import Path

# Configure logging to file and console
log_dir = os.path.expanduser("~/.local/share/thearchhive/logs")
os.makedirs(log_dir, exist_ok=True)
log_file = os.path.join(log_dir, "mcp-server.log")

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("mcp-server")

# Create Flask app with proper error handling
app = Flask(__name__)

# Default configuration
CONFIG_DIR = os.path.expanduser("~/.config/thearchhive")
MCP_CONFIG_PATH = os.path.join(CONFIG_DIR, "mcp_config.json")
MCP_PORT = 5678

def get_default_config():
    """Return default configuration"""
    return {
        "port": MCP_PORT,
        "snapshot_dir": os.path.expanduser("~/.local/share/thearchhive/snapshots"),
        "enable_command_execution": False,
        "safe_commands": ["pacman -Qi", "uname", "df", "free", "cat /proc/cpuinfo", "lspci"]
    }

def ensure_config_exists():
    """Ensure the MCP configuration file exists"""
    logger.info(f"Checking configuration in {CONFIG_DIR}")
    
    if not os.path.exists(CONFIG_DIR):
        logger.info(f"Creating config directory: {CONFIG_DIR}")
        os.makedirs(CONFIG_DIR, exist_ok=True)
    
    if not os.path.exists(MCP_CONFIG_PATH):
        logger.info(f"Creating default configuration: {MCP_CONFIG_PATH}")
        default_config = get_default_config()
        
        with open(MCP_CONFIG_PATH, 'w') as f:
            json.dump(default_config, f, indent=2)
        os.chmod(MCP_CONFIG_PATH, 0o600)  # Secure permissions
    
    # Ensure snapshot directory exists
    try:
        # Read config file directly here without calling load_config to avoid recursion
        with open(MCP_CONFIG_PATH, 'r') as f:
            config = json.load(f)
        
        snapshot_dir = os.path.expanduser(config.get("snapshot_dir", "~/.local/share/thearchhive/snapshots"))
        logger.info(f"Ensuring snapshot directory exists: {snapshot_dir}")
        
        if not os.path.exists(snapshot_dir):
            os.makedirs(snapshot_dir, exist_ok=True)
    except Exception as e:
        logger.error(f"Error ensuring snapshot directory: {str(e)}")
        # If reading config fails, ensure default snapshot directory exists
        default_snapshot_dir = os.path.expanduser("~/.local/share/thearchhive/snapshots")
        if not os.path.exists(default_snapshot_dir):
            os.makedirs(default_snapshot_dir, exist_ok=True)

def load_config():
    """Load MCP configuration"""
    try:
        # First make sure config file exists
        ensure_config_exists()
        
        logger.info(f"Loading configuration from {MCP_CONFIG_PATH}")
        
        with open(MCP_CONFIG_PATH, 'r') as f:
            config = json.load(f)
            
        # Ensure snapshot_dir is expanded
        if "snapshot_dir" in config:
            config["snapshot_dir"] = os.path.expanduser(config["snapshot_dir"])
            
        return config
    except Exception as e:
        logger.error(f"Error loading configuration: {str(e)}")
        # Return default config if loading fails
        return get_default_config()

def run_command(command):
    """Run a system command and return its output"""
    try:
        logger.info(f"Running command: {command}")
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "error": result.stderr
        }
    except Exception as e:
        logger.error(f"Error running command: {str(e)}")
        return {
            "success": False,
            "output": "",
            "error": str(e)
        }

@app.route('/system/info', methods=['GET'])
def system_info():
    """Get basic system information"""
    try:
        logger.info("Retrieving system information")
        
        # Gather system information
        system_data = {
            "hostname": platform.node(),
            "os": {
                "name": "Arch Linux",
                "kernel": platform.release(),
                "arch": platform.machine(),
            },
            "cpu": {
                "model": "",
                "cores": psutil.cpu_count(logical=False) or 1,
                "threads": psutil.cpu_count(logical=True) or 1,
                "usage_percent": psutil.cpu_percent()
            },
            "memory": {
                "total_gb": round(psutil.virtual_memory().total / (1024**3), 2),
                "used_gb": round(psutil.virtual_memory().used / (1024**3), 2),
                "free_gb": round(psutil.virtual_memory().available / (1024**3), 2),
                "percent_used": psutil.virtual_memory().percent
            },
            "disk": {
                "total_gb": round(psutil.disk_usage('/').total / (1024**3), 2),
                "used_gb": round(psutil.disk_usage('/').used / (1024**3), 2),
                "free_gb": round(psutil.disk_usage('/').free / (1024**3), 2),
                "percent_used": psutil.disk_usage('/').percent
            }
        }
        
        # Safely get CPU model
        try:
            cpu_info = subprocess.getoutput("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2").strip()
            system_data["cpu"]["model"] = cpu_info
        except Exception as e:
            logger.warning(f"Could not get CPU model: {str(e)}")
            system_data["cpu"]["model"] = "Unknown"
        
        # Get GPU information if available
        try:
            gpu_info = run_command("lspci | grep -i 'vga\\|3d\\|2d'")
            if gpu_info["success"] and gpu_info["output"]:
                system_data["gpu"] = gpu_info["output"]
        except Exception as e:
            logger.warning(f"Could not get GPU info: {str(e)}")
        
        return jsonify(system_data)
    except Exception as e:
        logger.error(f"Error in system_info endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/packages/installed', methods=['GET'])
def installed_packages():
    """Get list of explicitly installed packages"""
    try:
        logger.info("Retrieving installed packages")
        result = run_command("pacman -Qe")
        if result["success"]:
            packages = []
            for line in result["output"].splitlines():
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        packages.append({
                            "name": parts[0],
                            "version": parts[1]
                        })
            return jsonify({"packages": packages})
        else:
            logger.error(f"Error getting installed packages: {result['error']}")
            return jsonify({"error": result["error"]}), 500
    except Exception as e:
        logger.error(f"Error in installed_packages endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/claudescript/encode', methods=['POST'])
def claudescript_encode():
    """Encode data into ClaudeScript format"""
    try:
        logger.info("Encoding data to ClaudeScript")
        data = request.get_json()
        if not data:
            return jsonify({"error": "No data provided"}), 400
            
        # Implement ClaudeScript encoding logic
        claudescript = []
        
        # Process packages
        if "packages" in data:
            for pkg in data["packages"]:
                claudescript.append(f"p:{pkg['name']}-{pkg['version']}")
        
        # Process system info
        if "system" in data:
            if "kernel" in data["system"]:
                claudescript.append(f"k:{data['system']['kernel']}")
            if "cpu" in data["system"]:
                claudescript.append(f"c:{data['system']['cpu']}")
            if "memory" in data["system"]:
                claudescript.append(f"m:{data['system']['memory']}")
        
        return jsonify({"claudescript": claudescript})
    except Exception as e:
        logger.error(f"Error in claudescript_encode endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/execute', methods=['POST'])
def execute_command():
    """Execute a command if it's allowed"""
    try:
        logger.info("Command execution requested")
        config = load_config()
        if not config.get("enable_command_execution", False):
            logger.warning("Command execution is disabled")
            return jsonify({"error": "Command execution is disabled"}), 403
            
        data = request.get_json()
        if not data or "command" not in data:
            return jsonify({"error": "No command provided"}), 400
            
        command = data["command"]
        logger.info(f"Requested command: {command}")
        
        # Check if command is in the safe list or starts with a safe prefix
        allowed = False
        for safe_cmd in config.get("safe_commands", []):
            if command == safe_cmd or command.startswith(safe_cmd + " "):
                allowed = True
                break
        
        if not allowed:
            logger.warning(f"Command not allowed: {command}")
            return jsonify({"error": "Command not allowed"}), 403
            
        result = run_command(command)
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error in execute_command endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/snapshot/create', methods=['POST'])
def create_snapshot():
    """Create a system snapshot in ClaudeScript format"""
    try:
        logger.info("Creating system snapshot")
        config = load_config()
        timestamp = subprocess.getoutput("date +%Y%m%d%H%M%S")
        
        # Ensure snapshot_dir is expanded and exists
        snapshot_dir = os.path.expanduser(config["snapshot_dir"])
        os.makedirs(snapshot_dir, exist_ok=True)
        
        snapshot_path = os.path.join(snapshot_dir, f"snapshot_{timestamp}.json")
        logger.info(f"Snapshot will be saved to: {snapshot_path}")
        
        # Gather system information
        try:
            system_info_response = system_info().get_json()
        except Exception as e:
            logger.error(f"Error getting system info: {str(e)}")
            system_info_response = {}
        
        try:
            packages_response = installed_packages().get_json()
        except Exception as e:
            logger.error(f"Error getting packages: {str(e)}")
            packages_response = {"packages": []}
        
        # Combine data
        snapshot_data = {
            "timestamp": timestamp,
            "system": system_info_response,
            "packages": packages_response.get("packages", [])
        }
        
        # Get ClaudeScript representation
        claudescript = []
        
        # Add kernel info if available
        if "os" in system_info_response and "kernel" in system_info_response["os"]:
            claudescript.append(f"k:{system_info_response['os']['kernel']}")
            
        # Add CPU info if available
        if "cpu" in system_info_response and "model" in system_info_response["cpu"]:
            claudescript.append(f"c:{system_info_response['cpu']['model']}")
            
        # Add memory info if available
        if "memory" in system_info_response and "total_gb" in system_info_response["memory"]:
            claudescript.append(f"m:{system_info_response['memory']['total_gb']}GB")
            
        # Add package info
        for pkg in packages_response.get("packages", []):
            claudescript.append(f"p:{pkg['name']}-{pkg['version']}")
            
        snapshot_data["claudescript"] = claudescript
        
        # Save snapshot
        try:
            with open(snapshot_path, 'w') as f:
                json.dump(snapshot_data, f, indent=2)
            logger.info(f"Snapshot saved to {snapshot_path}")
        except Exception as e:
            logger.error(f"Error saving snapshot: {str(e)}")
            return jsonify({"error": f"Failed to save snapshot: {str(e)}"}), 500
        
        return jsonify({
            "success": True,
            "snapshot_path": snapshot_path,
            "claudescript": snapshot_data.get("claudescript", [])
        })
    except Exception as e:
        logger.error(f"Error in create_snapshot endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/snapshots', methods=['GET'])
def list_snapshots():
    """List available snapshots"""
    try:
        logger.info("Listing available snapshots")
        config = load_config()
        snapshot_dir = os.path.expanduser(config["snapshot_dir"])
        os.makedirs(snapshot_dir, exist_ok=True)
        
        snapshots = []
        
        if os.path.exists(snapshot_dir):
            for filename in os.listdir(snapshot_dir):
                if filename.startswith("snapshot_") and filename.endswith(".json"):
                    snapshot_path = os.path.join(snapshot_dir, filename)
                    try:
                        with open(snapshot_path, 'r') as f:
                            snapshot = json.load(f)
                            snapshots.append({
                                "filename": filename,
                                "timestamp": snapshot.get("timestamp", ""),
                                "path": snapshot_path
                            })
                    except Exception as e:
                        logger.warning(f"Could not read snapshot {filename}: {str(e)}")
        
        return jsonify({"snapshots": snapshots})
    except Exception as e:
        logger.error(f"Error in list_snapshots endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/config/backup', methods=['POST'])
def create_config_backup():
    """Create a backup of configuration files"""
    try:
        logger.info("Creating configuration backup")
        backup_script = os.path.expanduser("~/.config/thearchhive/scripts/backup.sh")
        
        if not os.path.exists(backup_script):
            logger.error(f"Backup script not found: {backup_script}")
            return jsonify({"error": "Backup script not found"}), 404
            
        # This would be connected to the backup.sh script
        result = run_command(f"bash {backup_script}")
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error in create_config_backup endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Simple health check endpoint"""
    return jsonify({"status": "ok", "message": "MCP Server is running"})

def main():
    """Main function for running the server"""
    try:
        # Log startup information
        logger.info(f"Starting MCP Server v1.0.0")
        logger.info(f"Python version: {sys.version}")
        logger.info(f"Platform: {platform.platform()}")
        logger.info(f"Working directory: {os.getcwd()}")
        
        # Ensure configurations exist
        ensure_config_exists()
        
        # Load configuration
        config = load_config()
        
        # Get port from config
        port = config.get("port", MCP_PORT)
        logger.info(f"Configured to run on port {port}")
        
        # Start server
        logger.info(f"Starting server on http://127.0.0.1:{port}")
        app.run(host='127.0.0.1', port=port, debug=False)
    except Exception as e:
        logger.error(f"Fatal error starting MCP server: {str(e)}")
        sys.exit(1)

if __name__ == '__main__':
    main()
