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

@app.route('/system/windowmanager', methods=['GET'])
def window_manager():
    """Get information about the installed window manager"""
    try:
        logger.info("Retrieving window manager information")
        
        # Try multiple approaches to detect the window manager
        wm_info = {"detected": False, "name": "Unknown", "status": "Unknown"}
        
        # Check for common WM and DE packages
        wm_packages = ["hyprland", "sway", "i3", "xmonad", "dwm", "openbox", "bspwm", 
                     "gnome-shell", "kwin", "xfwm4", "awesome", "qtile"]
        
        for wm in wm_packages:
            result = run_command(f"pacman -Qi {wm} 2>/dev/null || true")
            if result["success"] and "Name" in result["output"]:
                wm_info["detected"] = True
                wm_info["name"] = wm
                wm_info["status"] = "Installed"
                
                # Check if it's running
                result = run_command(f"pgrep {wm} 2>/dev/null || true")
                if result["success"] and result["output"].strip():
                    wm_info["status"] = "Running"
                break
        
        return jsonify(wm_info)
    except Exception as e:
        logger.error(f"Error in window_manager endpoint: {str(e)}")
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
            
        # Enhanced security checks
        if "rm -rf" in command or ":(){ :|:& };" in command:
            logger.error(f"Potentially dangerous command blocked: {command}")
            return jsonify({"error": "Command contains potentially dangerous patterns"}), 403
            
        # Execute the command with timeout for safety
        try:
            result = subprocess.run(
                command, 
                shell=True, 
                capture_output=True, 
                text=True,
                timeout=30  # 30 second timeout for commands
            )
            
            response = {
                "success": result.returncode == 0,
                "output": result.stdout,
                "error": result.stderr,
                "returncode": result.returncode
            }
            
            logger.info(f"Command executed with return code: {result.returncode}")
            return jsonify(response)
            
        except subprocess.TimeoutExpired:
            logger.error(f"Command timed out: {command}")
            return jsonify({
                "success": False, 
                "output": "", 
                "error": "Command execution timed out (30s limit)",
                "returncode": -1
            }), 408
            
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

# Terminal output validation

@app.route('/script/validate', methods=['POST'])
def validate_script():
    """Validate a script by running it with validation points"""
    try:
        logger.info("Script validation requested")
        data = request.get_json()
        
        if not data or "script" not in data:
            return jsonify({"error": "No script provided"}), 400
            
        script_content = data["script"]
        validation_level = data.get("validation_level", "normal")  # Options: minimal, normal, strict
        
        # Generate a validation wrapper for the script
        validated_script, validation_id = generate_validation_wrapper(script_content, validation_level)
        
        # Save the validated script
        script_dir = os.path.expanduser("~/.local/share/thearchhive/scripts")
        os.makedirs(script_dir, exist_ok=True)
        
        script_path = os.path.join(script_dir, f"validated_script_{validation_id}.sh")
        with open(script_path, 'w') as f:
            f.write(validated_script)
        os.chmod(script_path, 0o755)
        
        return jsonify({
            "validation_id": validation_id,
            "script_path": script_path,
            "validation_level": validation_level
        })
    except Exception as e:
        logger.error(f"Error in validate_script endpoint: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/script/results/<validation_id>', methods=['GET'])
def get_validation_results(validation_id):
    """Get the results of a validated script execution"""
    try:
        logger.info(f"Retrieving validation results for ID: {validation_id}")
        
        # Check if results file exists
        results_dir = os.path.expanduser("~/.local/share/thearchhive/validation_results")
        results_path = os.path.join(results_dir, f"{validation_id}.json")
        
        if not os.path.exists(results_path):
            return jsonify({"error": "Validation results not found"}), 404
            
        with open(results_path, 'r') as f:
            results = json.load(f)
            
        return jsonify(results)
    except Exception as e:
        logger.error(f"Error retrieving validation results: {str(e)}")
        return jsonify({"error": str(e)}), 500

def generate_validation_wrapper(script_content, validation_level):
    """Generate a script wrapper with validation checkpoints"""
    # Generate a unique ID for this validation run
    validation_id = f"{int(time.time())}_{random.randint(1000, 9999)}"
    
    # Create results directory
    results_dir = os.path.expanduser("~/.local/share/thearchhive/validation_results")
    os.makedirs(results_dir, exist_ok=True)
    results_path = os.path.join(results_dir, f"{validation_id}.json")
    
    # Create the validation wrapper
    wrapper = f"""#!/bin/bash

# TheArchHive Validation Wrapper
# Validation ID: {validation_id}
# Level: {validation_level}
# Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

# Initialize validation results file
cat > {results_path} << 'INIT_JSON'
{{
    "validation_id": "{validation_id}",
    "start_time": "{datetime.datetime.now().isoformat()}",
    "status": "running",
    "steps": []
}}
INIT_JSON

# Function to log validation results
log_validation() {{
    step_num=$1
    command=$2
    exit_code=$3
    output=$4
    
    # Create temporary JSON for this step
    step_json=$(cat << EOF
    {{
        "step": $step_num,
        "command": $(echo "$command" | jq -Rs .),
        "exit_code": $exit_code,
        "output": $(echo "$output" | jq -Rs .),
        "timestamp": "$(date -Iseconds)"
    }}
EOF
    )
    
    # Update the results file
    tmp_file=$(mktemp)
    jq ".steps += [$step_json]" {results_path} > "$tmp_file" && mv "$tmp_file" {results_path}
}}

# Set bash options based on validation level
"""
    
    # Add validation level settings
    if validation_level == "strict":
        wrapper += """set -euo pipefail  # Exit on error, undefined vars, and pipe failures
"""
    elif validation_level == "normal":
        wrapper += """set -eo pipefail  # Exit on error and pipe failures
"""
    else:  # minimal
        wrapper += """set -e  # Exit on error
"""
    
    # Process the original script, adding validation
    lines = script_content.split('\n')
    processed_script = []
    step_num = 0
    
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith('#') and not stripped.startswith('function ') and not stripped.startswith('if ') and not stripped.startswith('else') and not stripped.startswith('fi') and not stripped.startswith('for ') and not stripped.startswith('done') and not stripped.startswith('while ') and not stripped.startswith('do '):
            # This looks like a command line, add validation
            step_num += 1
            processed_script.append(f"""
# Step {step_num}
echo "Executing: {stripped}"
validation_output_{step_num}=$({{ {stripped}; }} 2>&1)
validation_exit_{step_num}=$?
echo "$validation_output_{step_num}"
log_validation {step_num} "{stripped}" $validation_exit_{step_num} "$validation_output_{step_num}"
if [ $validation_exit_{step_num} -ne 0 ]; then
    echo "Command failed with exit code $validation_exit_{step_num}"
    {"exit $validation_exit_{step_num}" if validation_level != "minimal" else "# Continue despite error in minimal mode"}
fi
""")
        else:
            # Pass through other lines (comments, control structures, etc.)
            processed_script.append(line)
    
    # Add completion marker
    wrapper += '\n'.join(processed_script) + f"""

# Mark validation as complete
tmp_file=$(mktemp)
jq '.status = "completed" | .end_time = "{datetime.datetime.now().isoformat()}"' {results_path} > "$tmp_file" && mv "$tmp_file" {results_path}

echo "Script execution completed. Validation ID: {validation_id}"
"""
    
    return wrapper, validation_id

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
