#!/usr/bin/env python3

"""
ClaudeScript: A language for encoding Arch Linux configurations
Part of TheArchHive project
"""

import os
import re
import json
import argparse
import subprocess
from typing import Dict, List, Any, Union, Optional, Tuple

# ClaudeScript prefixes and their meanings
PREFIX_MAP = {
    "p:": "package",         # Package information (name-version)
    "k:": "kernel",          # Kernel information
    "c:": "cpu",             # CPU information
    "m:": "memory",          # Memory information
    "d:": "disk",            # Disk information
    "g:": "gpu",             # GPU information
    "f:": "file",            # File path and content hash
    "cf:": "config",         # Configuration file with settings
    "s:": "service",         # System service status
    "i:": "input",           # Input device
    "o:": "output",          # Output device
    "n:": "network",         # Network configuration
    "cmd:": "command",       # Command to execute
    "r:": "runtime",         # Runtime configuration
    "b:": "build",           # Build configuration
    "v:": "variable",        # Environment variable
    "t:": "tweak",           # System tweak
    "e:": "error",           # Error or warning
    "a:": "alias",           # Command alias
    "h:": "hook",            # System hook
}

# ClaudeScript specification version
SPEC_VERSION = "0.2.0"

class ClaudeScript:
    """
    ClaudeScript implementation for encoding and decoding Arch Linux configurations
    """
    
    def __init__(self, spec_file: Optional[str] = None):
        """Initialize ClaudeScript with optional specification file"""
        self.spec_version = SPEC_VERSION
        
        # Load from spec file if provided
        if spec_file and os.path.exists(spec_file):
            with open(spec_file, 'r') as f:
                spec_data = json.load(f)
                self.spec_version = spec_data.get('version', SPEC_VERSION)
                self.prefix_map = spec_data.get('prefixes', PREFIX_MAP)
        else:
            self.prefix_map = PREFIX_MAP
    
    def encode(self, data_type: str, data: str) -> str:
        """
        Encode data into ClaudeScript format
        
        Args:
            data_type: Type of data (e.g., 'package', 'kernel')
            data: The data to encode
            
        Returns:
            ClaudeScript encoded string
        """
        # Find the prefix for the data type
        prefix = None
        for p, t in self.prefix_map.items():
            if t == data_type:
                prefix = p
                break
        
        if not prefix:
            raise ValueError(f"Unknown data type: {data_type}")
        
        # Clean data for encoding
        cleaned_data = self._clean_for_encoding(data)
        
        return f"{prefix}{cleaned_data}"
    
    def decode(self, claudescript: str) -> Tuple[str, str]:
        """
        Decode a ClaudeScript string into data type and value
        
        Args:
            claudescript: ClaudeScript encoded string
            
        Returns:
            Tuple of (data_type, data_value)
        """
        for prefix, data_type in self.prefix_map.items():
            if claudescript.startswith(prefix):
                data = claudescript[len(prefix):]
                return data_type, data
        
        raise ValueError(f"Invalid ClaudeScript format: {claudescript}")
    
    def _clean_for_encoding(self, data: str) -> str:
        """Clean data for encoding to ClaudeScript"""
        # Replace characters that might cause issues
        return data.replace("\n", "\\n").replace("\r", "\\r")
    
    def _parse_for_decoding(self, data: str) -> str:
        """Parse data from ClaudeScript format"""
        # Convert escaped characters back
        return data.replace("\\n", "\n").replace("\\r", "\r")
    
    def encode_package(self, name: str, version: str) -> str:
        """Encode package information"""
        return self.encode('package', f"{name}-{version}")
    
    def encode_kernel(self, kernel_version: str) -> str:
        """Encode kernel information"""
        return self.encode('kernel', kernel_version)
    
    def encode_config_file(self, file_path: str, key_value: Dict[str, str]) -> str:
        """
        Encode configuration file with key-value pairs
        
        Example: cf:/etc/fstab:defaults=relatime,noatime
        """
        # Convert key-value pairs to string
        kv_string = ",".join([f"{k}={v}" for k, v in key_value.items()])
        return self.encode('config', f"{file_path}:{kv_string}")
    
    def encode_command(self, command: str) -> str:
        """Encode a command to execute"""
        return self.encode('command', command)
    
    def encode_runtime_config(self, application: str, setting: str) -> str:
        """
        Encode runtime configuration
        
        Example: r:neovim:set number
        """
        return self.encode('runtime', f"{application}:{setting}")
    
    def encode_tweak(self, component: str, tweak: str) -> str:
        """
        Encode system tweak
        
        Example: t:sysctl:vm.swappiness=10
        """
        return self.encode('tweak', f"{component}:{tweak}")
    
    def decode_package(self, claudescript: str) -> Dict[str, str]:
        """Decode package information from ClaudeScript"""
        data_type, data = self.decode(claudescript)
        
        if data_type != 'package':
            raise ValueError(f"Not a package ClaudeScript: {claudescript}")
        
        # Parse package-version format
        match = re.match(r"(.+)-([^-]+)$", data)
        if match:
            name, version = match.groups()
            return {'name': name, 'version': version}
        
        # Fallback if no version specified
        return {'name': data, 'version': 'unknown'}
    
    def decode_config_file(self, claudescript: str) -> Dict[str, Any]:
        """Decode configuration file information from ClaudeScript"""
        data_type, data = self.decode(claudescript)
        
        if data_type != 'config':
            raise ValueError(f"Not a config ClaudeScript: {claudescript}")
        
        # Split into file path and key-value pairs
        parts = data.split(':', 1)
        if len(parts) < 2:
            return {'path': data, 'settings': {}}
        
        file_path, kv_string = parts
        
        # Parse key-value pairs
        settings = {}
        for kv in kv_string.split(','):
            if '=' in kv:
                k, v = kv.split('=', 1)
                settings[k] = v
        
        return {'path': file_path, 'settings': settings}
    
    def decode_runtime_config(self, claudescript: str) -> Dict[str, str]:
        """Decode runtime configuration from ClaudeScript"""
        data_type, data = self.decode(claudescript)
        
        if data_type != 'runtime':
            raise ValueError(f"Not a runtime config ClaudeScript: {claudescript}")
        
        # Split into application and setting
        parts = data.split(':', 1)
        if len(parts) < 2:
            return {'application': data, 'setting': ''}
        
        application, setting = parts
        return {'application': application, 'setting': setting}
    
    def encode_snapshot(self, snapshot_data: Dict[str, Any]) -> List[str]:
        """
        Encode a system snapshot into ClaudeScript strings
        
        Args:
            snapshot_data: Dictionary with system snapshot data
            
        Returns:
            List of ClaudeScript strings
        """
        claudescript_lines = []
        
        # Encode kernel information
        if 'kernel' in snapshot_data:
            claudescript_lines.append(self.encode_kernel(snapshot_data['kernel']))
        
        # Encode CPU information
        if 'cpu' in snapshot_data:
            claudescript_lines.append(self.encode('cpu', snapshot_data['cpu']))
        
        # Encode memory information
        if 'memory' in snapshot_data:
            claudescript_lines.append(self.encode('memory', str(snapshot_data['memory'])))
        
        # Encode GPU information
        if 'gpu' in snapshot_data:
            claudescript_lines.append(self.encode('gpu', snapshot_data['gpu']))
        
        # Encode packages
        if 'packages' in snapshot_data:
            for pkg in snapshot_data['packages']:
                name = pkg.get('name', '')
                version = pkg.get('version', '')
                if name and version:
                    claudescript_lines.append(self.encode_package(name, version))
        
        # Encode configuration files
        if 'config_files' in snapshot_data:
            for config_file in snapshot_data['config_files']:
                path = config_file.get('path', '')
                settings = config_file.get('settings', {})
                if path:
                    claudescript_lines.append(self.encode_config_file(path, settings))
        
        return claudescript_lines
    
    def decode_snapshot(self, claudescript_lines: List[str]) -> Dict[str, Any]:
        """
        Decode ClaudeScript strings into a system snapshot
        
        Args:
            claudescript_lines: List of ClaudeScript strings
            
        Returns:
            Dictionary with system snapshot data
        """
        snapshot = {
            'packages': [],
            'config_files': [],
            'tweaks': [],
            'runtime_configs': []
        }
        
        for line in claudescript_lines:
            try:
                data_type, data = self.decode(line)
                
                if data_type == 'package':
                    pkg_info = self.decode_package(line)
                    snapshot['packages'].append(pkg_info)
                elif data_type == 'kernel':
                    snapshot['kernel'] = data
                elif data_type == 'cpu':
                    snapshot['cpu'] = data
                elif data_type == 'memory':
                    snapshot['memory'] = data
                elif data_type == 'gpu':
                    snapshot['gpu'] = data
                elif data_type == 'config':
                    config_info = self.decode_config_file(line)
                    snapshot['config_files'].append(config_info)
                elif data_type == 'tweak':
                    parts = data.split(':', 1)
                    if len(parts) == 2:
                        component, tweak = parts
                        snapshot['tweaks'].append({
                            'component': component,
                            'tweak': tweak
                        })
                elif data_type == 'runtime':
                    runtime_info = self.decode_runtime_config(line)
                    snapshot['runtime_configs'].append(runtime_info)
            except ValueError as e:
                print(f"Warning: {e}")
        
        return snapshot
    
    def save_spec(self, file_path: str) -> None:
        """Save the ClaudeScript specification to a file"""
        spec_data = {
            'version': self.spec_version,
            'prefixes': self.prefix_map
        }
        
        with open(file_path, 'w') as f:
            json.dump(spec_data, f, indent=2)
    
    def get_system_snapshot(self) -> Dict[str, Any]:
        """
        Get a snapshot of the current system
        
        Returns:
            Dictionary with system snapshot data
        """
        snapshot = {}
        
        # Get kernel version
        try:
            kernel = subprocess.check_output(['uname', '-r']).decode().strip()
            snapshot['kernel'] = kernel
        except:
            pass
        
        # Get CPU information
        try:
            cpu = subprocess.check_output("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2", 
                                          shell=True).decode().strip()
            snapshot['cpu'] = cpu
        except:
            pass
        
        # Get memory information
        try:
            total_mem = subprocess.check_output("free -m | grep Mem | awk '{print $2}'", 
                                               shell=True).decode().strip()
            snapshot['memory'] = f"{total_mem}MB"
        except:
            pass
        
        # Get GPU information
        try:
            gpu = subprocess.check_output("lspci | grep -i 'vga\\|3d\\|2d' | head -1", 
                                         shell=True).decode().strip()
            snapshot['gpu'] = gpu
        except:
            pass
        
        # Get explicitly installed packages
        try:
            packages = []
            pkg_output = subprocess.check_output(['pacman', '-Qe']).decode().strip()
            for line in pkg_output.split('\n'):
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        packages.append({
                            'name': parts[0],
                            'version': parts[1]
                        })
            snapshot['packages'] = packages
        except:
            snapshot['packages'] = []
        
        return snapshot
    
    def create_system_snapshot(self) -> List[str]:
        """
        Create a ClaudeScript snapshot of the current system
        
        Returns:
            List of ClaudeScript strings
        """
        snapshot_data = self.get_system_snapshot()
        return self.encode_snapshot(snapshot_data)

def main():
    """Main function for CLI usage"""
    parser = argparse.ArgumentParser(description='ClaudeScript: A language for encoding Arch Linux configurations')
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # encode command
    encode_parser = subparsers.add_parser('encode', help='Encode data into ClaudeScript')
    encode_parser.add_argument('type', help='Data type')
    encode_parser.add_argument('data', help='Data to encode')
    
    # decode command
    decode_parser = subparsers.add_parser('decode', help='Decode ClaudeScript string')
    decode_parser.add_argument('script', help='ClaudeScript string')
    
    # snapshot command
    snapshot_parser = subparsers.add_parser('snapshot', help='Create a system snapshot')
    snapshot_parser.add_argument('--output', '-o', help='Output file')
    
    # spec command
    spec_parser = subparsers.add_parser('spec', help='Save ClaudeScript specification')
    spec_parser.add_argument('--output', '-o', required=True, help='Output file')
    
    args = parser.parse_args()
    
    # Initialize ClaudeScript
    cs = ClaudeScript()
    
    if args.command == 'encode':
        try:
            result = cs.encode(args.type, args.data)
            print(result)
        except ValueError as e:
            print(f"Error: {e}")
            return 1
    elif args.command == 'decode':
        try:
            data_type, data = cs.decode(args.script)
            print(f"Type: {data_type}")
            print(f"Data: {data}")
        except ValueError as e:
            print(f"Error: {e}")
            return 1
    elif args.command == 'snapshot':
        try:
            snapshot_lines = cs.create_system_snapshot()
            
            if args.output:
                with open(args.output, 'w') as f:
                    for line in snapshot_lines:
                        f.write(f"{line}\n")
                print(f"Snapshot saved to {args.output}")
            else:
                for line in snapshot_lines:
                    print(line)
        except Exception as e:
            print(f"Error creating snapshot: {e}")
            return 1
    elif args.command == 'spec':
        try:
            cs.save_spec(args.output)
            print(f"Specification saved to {args.output}")
        except Exception as e:
            print(f"Error saving specification: {e}")
            return 1
    else:
        parser.print_help()
    
    return 0

if __name__ == '__main__':
    exit(main())
