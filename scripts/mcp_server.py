#!/usr/bin/env python3
# TheArchHive - Model Context Protocol (MCP) Server
# This server connects Claude to the Arch Linux system

import os
import sys
import json
import time
import subprocess
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import psutil  # Make sure to install with: pip install psutil

VERSION = "0.1.0"
CONFIG_FILE = os.path.expanduser("~/.config/thearchhive/mcp_config.json")
DEFAULT_PORT = 7424  # "ARCH" on a phone keypad

# Default configuration
DEFAULT_CONFIG = {
    "port": DEFAULT_PORT,
    "allowed_commands": ["pacman", "neofetch", "ls", "cat", "grep", "systemctl"],
    "log_file": os.path.expanduser("~/.config/thearchhive/mcp.log"),
    "debug_mode": False,
    "auth_token": None  # Will be generated on first run
}


class MCPServer:
    def __init__(self, config_path=CONFIG_FILE):
        self.config_path = config_path
        self.config = self.load_config()
        self.ensure_auth_token()
        self.log(f"MCP Server v{VERSION} initialized")

    def load_config(self):
        """Load configuration or create default if doesn't exist"""
        try:
            if os.path.exists(self.config_path):
                with open(self.config_path, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults for any missing keys
                    for key, value in DEFAULT_CONFIG.items():
                        if key not in config:
                            config[key] = value
                    return config
            else:
                # Create config directory if it doesn't exist
                os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
                # Create and save default config
                with open(self.config_path, 'w') as f:
                    json.dump(DEFAULT_CONFIG, f, indent=2)
                return DEFAULT_CONFIG.copy()
        except Exception as e:
            print(f"Error loading config: {e}")
            return DEFAULT_CONFIG.copy()

    def ensure_auth_token(self):
        """Ensure auth token exists, generate if needed"""
        if not self.config.get("auth_token"):
            import secrets
            self.config["auth_token"] = secrets.token_hex(16)
            self.save_config()
            print(f"Generated new auth token: {self.config['auth_token']}")
            print("Use this token to authenticate with the MCP server")

    def save_config(self):
        """Save configuration to file"""
        try:
            with open(self.config_path, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"Error saving config: {e}")

    def log(self, message):
        """Log a message to the log file"""
        log_file = self.config.get("log_file")
        if log_file:
            try:
                with open(log_file, 'a') as f:
                    f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {message}\n")
            except Exception as e:
                print(f"Error writing to log: {e}")
        
        if self.config.get("debug_mode"):
            print(message)

    def get_system_info(self):
        """Get system information"""
        try:
            info = {
                "timestamp": time.time(),
                "cpu": {
                    "percent": psutil.cpu_percent(interval=0.1),
                    "cores": psutil.cpu_count(),
                    "physical_cores": psutil.cpu_count(logical=False)
                },
                "memory": {
                    "total": psutil.virtual_memory().total,
                    "available": psutil.virtual_memory().available,
                    "percent": psutil.virtual_memory().percent
                },
                "disk": {
                    "total": psutil.disk_usage('/').total,
                    "used": psutil.disk_usage('/').used,
                    "free": psutil.disk_usage('/').free,
                    "percent": psutil.disk_usage('/').percent
                },
                "swap": {
                    "total": psutil.swap_memory().total,
                    "used": psutil.swap_memory().used,
                    "percent": psutil.swap_memory().percent
                }
            }
            
            # Add kernel info
            kernel_info = subprocess.check_output(["uname", "-a"]).decode().strip()
            info["kernel"] = kernel_info
            
            # Try to get pacman package count
            try:
                package_count = subprocess.check_output(["pacman", "-Qq", "|", "wc", "-l"], 
                                                      shell=True).decode().strip()
                info["packages"] = package_count
            except:
                info["packages"] = "unknown"
            
            return info
        except Exception as e:
            self.log(f"Error getting system info: {e}")
            return {"error": str(e)}

    def execute_command(self, command):
        """Execute a command and return the output"""
        # Extract the base command
        base_cmd = command.split()[0] if command else ""
        
        if base_cmd not in self.config.get("allowed_commands", []):
            return {"error": f"Command '{base_cmd}' is not allowed"}
        
        try:
            self.log(f"Executing command: {command}")
            output = subprocess.check_output(command, shell=True, timeout=10).decode()
            return {"output": output}
        except subprocess.TimeoutExpired:
            return {"error": "Command timed out"}
        except subprocess.CalledProcessError as e:
            return {"error": f"Command failed with exit code {e.returncode}: {e.output.decode() if e.output else ''}"}
        except Exception as e:
            return {"error": str(e)}


class MCPRequestHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        self.server_instance = args[2]
        super().__init__(*args, **kwargs)
    
    def _set_headers(self, status_code=200, content_type='application/json'):
        self.send_response(status_code)
        self.send_header('Content-type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()
    
    def _authenticate(self):
        """Check if request has valid authentication"""
        auth_token = self.server_instance.config.get("auth_token")
        if not auth_token:
            return True  # No auth required if token not set
        
        auth_header = self.headers.get('Authorization')
        if auth_header and auth_header.startswith('Bearer '):
            token = auth_header.split(' ')[1]
            return token == auth_token
        return False
    
    def do_OPTIONS(self):
        """Handle OPTIONS request (CORS preflight)"""
        self._set_headers()
    
    def do_GET(self):
        """Handle GET requests"""
        if not self._authenticate():
            self._set_headers(401)
            self.wfile.write(json.dumps({"error": "Unauthorized"}).encode())
            return
        
        if self.path == '/system':
            # Get system information
            info = self.server_instance.get_system_info()
            self._set_headers()
            self.wfile.write(json.dumps(info).encode())
        
        elif self.path == '/status':
            # Server status
            status = {
                "status": "running",
                "version": VERSION,
                "uptime": time.time() - self.server_instance.start_time
            }
            self._set_headers()
            self.wfile.write(json.dumps(status).encode())
        
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not found"}).encode())
    
    def do_POST(self):
        """Handle POST requests"""
        if not self._authenticate():
            self._set_headers(401)
            self.wfile.write(json.dumps({"error": "Unauthorized"}).encode())
            return
        
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length).decode()
        
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._set_headers(400)
            self.wfile.write(json.dumps({"error": "Invalid JSON"}).encode())
            return
        
        if self.path == '/execute':
            # Execute command
            if 'command' not in data:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Command is required"}).encode())
                return
            
            result = self.server_instance.execute_command(data['command'])
            self._set_headers()
            self.wfile.write(json.dumps(result).encode())
        
        elif self.path == '/claudescript':
            # Process ClaudeScript
            if 'script' not in data:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "ClaudeScript is required"}).encode())
                return
            
            # TODO: Implement ClaudeScript processing
            self._set_headers()
            self.wfile.write(json.dumps({"status": "ClaudeScript processing not implemented yet"}).encode())
        
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not found"}).encode())


def run_server(port):
    """Run the MCP server"""
    server_instance = MCPServer()
    server_instance.start_time = time.time()
    
    # Use server_instance as the third parameter to HTTPServer
    server = HTTPServer(('localhost', port), 
                        lambda *args: MCPRequestHandler(*args, server_instance))
    
    print(f"Starting MCP server on port {port}")
    server_instance.log(f"Server started on port {port}")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server_instance.log("Server stopped by user")
        print("Server stopped by user")
    except Exception as e:
        server_instance.log(f"Server error: {e}")
        print(f"Server error: {e}")


def main():
    try:
        # Load config to get port
        config_path = CONFIG_FILE
        if len(sys.argv) > 1 and sys.argv[1] == '--config':
            if len(sys.argv) > 2:
                config_path = sys.argv[2]
            else:
                print("Error: --config requires a path argument")
                sys.exit(1)
        
        # Initialize server to load config
        server = MCPServer(config_path)
        port = server.config.get('port', DEFAULT_PORT)
        
        # Run server
        run_server(port)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
