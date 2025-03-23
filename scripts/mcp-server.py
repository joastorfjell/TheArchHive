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

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Default configuration
CONFIG_DIR = os.path.expanduser("~/.config/thearchhive")
MCP_CONFIG_PATH = os.path.join(CONFIG_DIR, "mcp_config.json")
MCP_PORT = 5678

def ensure_config_exists():
    """Ensure the MCP configuration file exists"""
    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR)
    
    if not os.path.exists(MCP_CONFIG_PATH):
        default_config = {
            "port": MCP_PORT,
            "snapshot_dir": os.path.expanduser("~/.local/share/thearchhive/snapshots"),
            "enable_command_execution": False,
            "safe_commands": ["pacman -Qi", "uname", "df", "free"]
        }
        
        with open(MCP_CONFIG_PATH, 'w') as f:
            json.dump(default_config, f, indent=2)
        os.chmod(MCP_CONFIG_PATH, 0o600)  # Secure permissions
        
    # Ensure snapshot directory exists
    config = load_config()
    if not os.path.exists(config["snapshot_dir"]):
        os.makedirs(config["snapshot_dir"])

def load_config():
    """Load MCP configuration"""
    ensure_config_exists()
    with open(MCP_CONFIG_PATH, 'r') as f:
        return json.load(f)

def run_command(command):
    """Run a system command and return its output"""
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True)
        return {
            "success": result.returncode == 0,
            "output": result.stdout,
            "error": result.stderr
        }
    except Exception as e:
        return {
            "success": False,
            "output": "",
            "error": str(e)
        }

@app.route('/system/info', methods=['GET'])
def system_info():
    """Get basic system information"""
    try:
        # Gather system information
        system_data = {
            "hostname": platform.node(),
            "os": {
                "name": "Arch Linux",
                "kernel": platform.release(),
                "arch": platform.machine(),
            },
            "cpu": {
                "model": subprocess.getoutput("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2").strip(),
                "cores": psutil.cpu_count(logical=False),
                "threads": psutil.cpu_count(logical=True),
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
        
        # Get GPU information if available
        gpu_info = run_command("lspci | grep -i 'vga\\|3d\\|2d'")
        if gpu_info["success"]:
            system_data["gpu"] = gpu_info["output"]
        
        return jsonify(system_data)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/packages/installed', methods=['GET'])
def installed_packages():
    """Get list of explicitly installed packages"""
    try:
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
            return jsonify({"error": result["error"]}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/claudescript/encode', methods=['POST'])
def claudescript_encode():
    """Encode data into ClaudeScript format"""
    try:
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
        return jsonify({"error": str(e)}), 500

@app.route('/execute', methods=['POST'])
def execute_command():
    """Execute a command if it's allowed"""
    config = load_config()
    if not config.get("enable_command_execution", False):
        return jsonify({"error": "Command execution is disabled"}), 403
        
    try:
        data = request.get_json()
        if not data or "command" not in data:
            return jsonify({"error": "No command provided"}), 400
            
        command = data["command"]
        
        # Check if command is in the safe list or starts with a safe prefix
        allowed = False
        for safe_cmd in config.get("safe_commands", []):
            if command == safe_cmd or command.startswith(safe_cmd + " "):
                allowed = True
                break
        
        if not allowed:
            return jsonify({"error": "Command not allowed"}), 403
            
        result = run_command(command)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/snapshot/create', methods=['POST'])
def create_snapshot():
    """Create a system snapshot in ClaudeScript format"""
    try:
        config = load_config()
        timestamp = subprocess.getoutput("date +%Y%m%d%H%M%S")
        snapshot_path = os.path.join(config["snapshot_dir"], f"snapshot_{timestamp}.json")
        
        # Gather system information
        system_info_response = system_info().get_json()
        packages_response = installed_packages().get_json()
        
        # Combine data
        snapshot_data = {
            "timestamp": timestamp,
            "system": system_info_response,
            "packages": packages_response.get("packages", [])
        }
        
        # Get ClaudeScript representation
        claudescript_data = {
            "packages": packages_response.get("packages", []),
            "system": {
                "kernel": system_info_response.get("os", {}).get("kernel", ""),
                "cpu": system_info_response.get("cpu", {}).get("model", ""),
                "memory": f"{system_info_response.get('memory', {}).get('total_gb', 0)}GB"
            }
        }
        
        claudescript_response = claudescript_encode()
        if hasattr(claudescript_response, 'get_json'):
            snapshot_data["claudescript"] = claudescript_response.get_json().get("claudescript", [])
        
        # Save snapshot
        with open(snapshot_path, 'w') as f:
            json.dump(snapshot_data, f, indent=2)
        
        return jsonify({
            "success": True,
            "snapshot_path": snapshot_path,
            "claudescript": snapshot_data.get("claudescript", [])
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/snapshots', methods=['GET'])
def list_snapshots():
    """List available snapshots"""
    try:
        config = load_config()
        snapshot_dir = config["snapshot_dir"]
        snapshots = []
        
        if os.path.exists(snapshot_dir):
            for filename in os.listdir(snapshot_dir):
                if filename.startswith("snapshot_") and filename.endswith(".json"):
                    snapshot_path = os.path.join(snapshot_dir, filename)
                    with open(snapshot_path, 'r') as f:
                        snapshot = json.load(f)
                        snapshots.append({
                            "filename": filename,
                            "timestamp": snapshot.get("timestamp", ""),
                            "path": snapshot_path
                        })
        
        return jsonify({"snapshots": snapshots})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/config/backup', methods=['POST'])
def create_config_backup():
    """Create a backup of configuration files"""
    try:
        # This would be connected to the backup.sh script
        result = run_command("bash ~/.config/thearchhive/scripts/backup.sh")
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # Ensure configurations exist
    ensure_config_exists()
    config = load_config()
    
    # Start server
    port = config.get("port", MCP_PORT)
    app.run(host='127.0.0.1', port=port, debug=True)
    print(f"MCP Server running on http://127.0.0.1:{port}")
