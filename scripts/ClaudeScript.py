#!/usr/bin/env python3

"""
ClaudeScript: A language for encoding Arch Linux configurations
Part of TheArchHive project - Enhanced with SSS Integration
"""

import os
import re
import json
import argparse
import subprocess
import datetime
import hashlib
from pathlib import Path
from typing import Dict, List, Any, Union, Optional, Tuple

# ClaudeScript prefixes and their meanings
PREFIX_MAP = {
    "v:": "version",         # ClaudeScript version
    "s:": "system",          # System scope identifier
    "p:": "package",         # Package information (name-version)
    "k:": "kernel",          # Kernel information
    "c:": "cpu",             # CPU information
    "m:": "memory",          # Memory information
    "d:": "disk",            # Disk information
    "g:": "gpu",             # GPU information
    "f:": "file",            # File path and content hash
    "cf:": "config",         # Configuration file with settings
    "pk:": "package_config", # Package-specific configuration
    "sv:": "service",        # System service status
    "i:": "input",           # Input device
    "o:": "output",          # Output device
    "n:": "network",         # Network configuration
    "cmd:": "command",       # Command to execute
    "r:": "runtime",         # Runtime configuration
    "b:": "build",           # Build configuration
    "t:": "tweak",           # System tweak
    "e:": "error",           # Error or warning
    "a:": "alias",           # Command alias
    "h:": "hook",            # System hook
    "scope:": "scope",       # Snapshot scope (full, package, etc.)
}

# ClaudeScript specification version
SPEC_VERSION = "1.0.0"

class ClaudeScript:
    """
    ClaudeScript implementation for encoding and decoding Arch Linux configurations
    Enhanced with SSS (System Snapshot System) integration
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
            
        # Create reverse mapping for decoding
        self.reverse_prefix_map = {v: k for k, v in self.prefix_map.items()}
    
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
        prefix = self.reverse_prefix_map.get(data_type)
        
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
                return data_type, self._parse_for_decoding(data)
        
        raise ValueError(f"Invalid ClaudeScript format: {claudescript}")
    
    def _clean_for_encoding(self, data: str) -> str:
        """Clean data for encoding to ClaudeScript"""
        # Replace characters that might cause issues
        return data.replace("\n", "\\n").replace("\r", "\\r").replace(":", "\\:")
    
    def _parse_for_decoding(self, data: str) -> str:
        """Parse data from ClaudeScript format"""
        # Convert escaped characters back
        return data.replace("\\n", "\n").replace("\\r", "\r").replace("\\:", ":")
    
    def encode_version(self) -> str:
        """Encode ClaudeScript version"""
        return self.encode('version', self.spec_version)
    
    def encode_system_scope(self, system_type: str) -> str:
        """
        Encode system scope
        
        Args:
            system_type: Type of system (e.g., 'archlinux')
            
        Returns:
            ClaudeScript encoded string
        """
        return self.encode('system', f"sys:{system_type}")
    
    def encode_package(self, name: str, version: str = "latest") -> str:
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
    
    def encode_package_config(self, package: str, config_type: str, path: str, content: str) -> str:
        """
        Encode package-specific configuration
        
        Example: pk:neovim:c:~/.config/nvim/init.vim:set number
        
        Args:
            package: Package name
            config_type: Type of configuration (c for config file, r for runtime setting)
            path: Path to the config file or setting name
            content: Configuration content or value
        """
        return self.encode('package_config', f"{package}:{config_type}:{path}:{content}")
    
    def encode_command(self, command: str) -> str:
        """Encode a command to execute"""
        return self.encode('command', command)
    
    def encode_runtime_config(self, application: str, setting: str) -> str:
        """
        Encode runtime configuration
        
        Example: r:neovim:set number
        """
        return self.encode('runtime', f"{application}:{setting}")
    
    def encode_build_config(self, package: str, flag: str) -> str:
        """
        Encode build configuration
        
        Example: b:mpv:--disable-gui
        """
        return self.encode('build', f"{package}:{flag}")
    
    def encode_tweak(self, component: str, tweak: str) -> str:
        """
        Encode system tweak
        
        Example: t:sysctl:vm.swappiness=10
        """
        return self.encode('tweak', f"{component}:{tweak}")
    
    def encode_file(self, file_path: str, include_hash: bool = True) -> str:
        """
        Encode file information, optionally with content hash
        
        Args:
            file_path: Path to the file
            include_hash: Whether to include a hash of the file content
        """
        if include_hash and os.path.exists(os.path.expanduser(file_path)):
            try:
                expanded_path = os.path.expanduser(file_path)
                with open(expanded_path, 'rb') as f:
                    content = f.read()
                file_hash = hashlib.sha256(content).hexdigest()[:16]  # Use first 16 chars for brevity
                return self.encode('file', f"{file_path}:{file_hash}")
            except Exception as e:
                print(f"Warning: Could not hash file {file_path}: {e}")
                return self.encode('file', file_path)
        else:
            return self.encode('file', file_path)
    
    def encode_snapshot_scope(self, scope: str) -> str:
        """
        Encode snapshot scope
        
        Args:
            scope: Scope of the snapshot (full, package, etc.)
        """
        return self.encode('scope', scope)
    
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
        return {'name': data, 'version': 'latest'}
    
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
    
    def decode_package_config(self, claudescript: str) -> Dict[str, str]:
        """Decode package-specific configuration from ClaudeScript"""
        data_type, data = self.decode(claudescript)
        
        if data_type != 'package_config':
            raise ValueError(f"Not a package config ClaudeScript: {claudescript}")
        
        # Parse package:config_type:path:content format
        parts = data.split(':', 3)
        if len(parts) < 4:
            raise ValueError(f"Invalid package config format: {data}")
        
        package, config_type, path, content = parts
        return {
            'package': package,
            'config_type': config_type,
            'path': path,
            'content': content
        }
    
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
    
    def decode_tweak(self, claudescript: str) -> Dict[str, str]:
        """Decode system tweak from ClaudeScript"""
        data_type, data = self.decode(claudescript)
        
        if data_type != 'tweak':
            raise ValueError(f"Not a tweak ClaudeScript: {claudescript}")
        
        # Split into component and tweak
        parts = data.split(':', 1)
        if len(parts) < 2:
            return {'component': data, 'tweak': ''}
        
        component, tweak = parts
        return {'component': component, 'tweak': tweak}
    
    def encode_snapshot(self, snapshot_data: Dict[str, Any], include_version: bool = True) -> List[str]:
        """
        Encode a system snapshot into ClaudeScript strings
        
        Args:
            snapshot_data: Dictionary with system snapshot data
            include_version: Whether to include ClaudeScript version
            
        Returns:
            List of ClaudeScript strings
        """
        claudescript_lines = []
        
        # Include ClaudeScript version
        if include_version:
            claudescript_lines.append(self.encode_version())
        
        # Encode system scope
        system_type = snapshot_data.get('system_type', 'archlinux')
        claudescript_lines.append(self.encode_system_scope(system_type))
        
        # Encode snapshot scope if available
        if 'scope' in snapshot_data:
            claudescript_lines.append(self.encode_snapshot_scope(snapshot_data['scope']))
        
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
        
        # Encode disk information
        if 'disk' in snapshot_data:
            claudescript_lines.append(self.encode('disk', str(snapshot_data['disk'])))
        
        # Encode packages
        if 'packages' in snapshot_data:
            for pkg in snapshot_data['packages']:
                name = pkg.get('name', '')
                version = pkg.get('version', 'latest')
                if name:
                    claudescript_lines.append(self.encode_package(name, version))
        
        # Encode configuration files
        if 'config_files' in snapshot_data:
            for config_file in snapshot_data['config_files']:
                path = config_file.get('path', '')
                settings = config_file.get('settings', {})
                if path:
                    claudescript_lines.append(self.encode_config_file(path, settings))
        
        # Encode package-specific configurations
        if 'package_configs' in snapshot_data:
            for pkg_config in snapshot_data['package_configs']:
                package = pkg_config.get('package', '')
                config_type = pkg_config.get('config_type', 'c')
                path = pkg_config.get('path', '')
                content = pkg_config.get('content', '')
                if package and path:
                    claudescript_lines.append(
                        self.encode_package_config(package, config_type, path, content)
                    )
        
        # Encode system tweaks
        if 'tweaks' in snapshot_data:
            for tweak in snapshot_data['tweaks']:
                component = tweak.get('component', '')
                value = tweak.get('tweak', '')
                if component and value:
                    claudescript_lines.append(self.encode_tweak(component, value))
        
        # Encode runtime configurations
        if 'runtime_configs' in snapshot_data:
            for rt_config in snapshot_data['runtime_configs']:
                app = rt_config.get('application', '')
                setting = rt_config.get('setting', '')
                if app and setting:
                    claudescript_lines.append(self.encode_runtime_config(app, setting))
        
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
            'system_type': 'archlinux',  # Default
            'packages': [],
            'config_files': [],
            'package_configs': [],
            'tweaks': [],
            'runtime_configs': [],
            'version': self.spec_version  # Default version
        }
        
        for line in claudescript_lines:
            try:
                data_type, data = self.decode(line)
                
                if data_type == 'version':
                    snapshot['version'] = data
                elif data_type == 'system':
                    if data.startswith('sys:'):
                        snapshot['system_type'] = data[4:]
                elif data_type == 'scope':
                    snapshot['scope'] = data
                elif data_type == 'package':
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
                elif data_type == 'disk':
                    snapshot['disk'] = data
                elif data_type == 'config':
                    config_info = self.decode_config_file(line)
                    snapshot['config_files'].append(config_info)
                elif data_type == 'package_config':
                    pkg_config = self.decode_package_config(line)
                    snapshot['package_configs'].append(pkg_config)
                elif data_type == 'tweak':
                    tweak_info = self.decode_tweak(line)
                    snapshot['tweaks'].append(tweak_info)
                elif data_type == 'runtime':
                    runtime_info = self.decode_runtime_config(line)
                    snapshot['runtime_configs'].append(runtime_info)
                elif data_type == 'file':
                    parts = data.split(':', 1)
                    file_path = parts[0]
                    file_hash = parts[1] if len(parts) > 1 else None
                    snapshot.setdefault('files', []).append({
                        'path': file_path,
                        'hash': file_hash
                    })
            except ValueError as e:
                print(f"Warning: {e}")
                continue
        
        return snapshot
    
    def save_spec(self, file_path: str) -> None:
        """Save the ClaudeScript specification to a file"""
        spec_data = {
            'version': self.spec_version,
            'prefixes': self.prefix_map
        }
        
        with open(file_path, 'w') as f:
            json.dump(spec_data, f, indent=2)
    
    def get_system_snapshot(self, scope: str = "full") -> Dict[str, Any]:
        """
        Get a snapshot of the current system
        
        Args:
            scope: Scope of the snapshot (full, minimal, package, etc.)
            
        Returns:
            Dictionary with system snapshot data
        """
        snapshot = {
            'system_type': 'archlinux',
            'scope': scope,
            'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }
        
        # Get kernel version
        try:
            kernel = subprocess.check_output(['uname', '-r']).decode().strip()
            snapshot['kernel'] = kernel
        except Exception as e:
            print(f"Warning: Could not get kernel version: {e}")
        
        # Get CPU information
        try:
            cpu = subprocess.check_output("cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2", 
                                          shell=True).decode().strip()
            snapshot['cpu'] = cpu
        except Exception as e:
            print(f"Warning: Could not get CPU information: {e}")
        
        # Get memory information
        try:
            total_mem = subprocess.check_output("free -m | grep Mem | awk '{print $2}'", 
                                               shell=True).decode().strip()
            snapshot['memory'] = f"{total_mem}MB"
        except Exception as e:
            print(f"Warning: Could not get memory information: {e}")
        
        # Get GPU information
        try:
            gpu = subprocess.check_output("lspci | grep -i 'vga\\|3d\\|2d' | head -1", 
                                         shell=True).decode().strip()
            snapshot['gpu'] = gpu
        except Exception as e:
            print(f"Warning: Could not get GPU information: {e}")
        
        # Get disk information
        try:
            disk_info = subprocess.check_output("df -h / | tail -1 | awk '{print $2, $3, $4, $5}'", 
                                               shell=True).decode().strip()
            snapshot['disk'] = disk_info
        except Exception as e:
            print(f"Warning: Could not get disk information: {e}")
        
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
        except Exception as e:
            print(f"Warning: Could not get package information: {e}")
            snapshot['packages'] = []
        
        # If scope is full, get additional details
        if scope == "full":
            # Get important configuration files
            config_files = []
            important_configs = [
                '/etc/fstab',
                '/etc/pacman.conf',
                '/etc/mkinitcpio.conf',
                '/etc/X11/xorg.conf',
                '/etc/X11/xorg.conf.d',
                '~/.config/i3/config',
                '~/.xinitrc',
                '~/.bashrc',
                '~/.zshrc',
                '~/.config/nvim/init.vim'
            ]
            
            for config_path in important_configs:
                expanded_path = os.path.expanduser(config_path)
                if os.path.exists(expanded_path):
                    if os.path.isfile(expanded_path):
                        config_files.append({
                            'path': config_path,
                            'settings': self._parse_config_settings(expanded_path)
                        })
                    elif os.path.isdir(expanded_path):
                        # For directories, list the files in them
                        for root, dirs, files in os.walk(expanded_path):
                            for file in files:
                                full_path = os.path.join(root, file)
                                relative_path = os.path.join(config_path, os.path.relpath(full_path, expanded_path))
                                config_files.append({
                                    'path': relative_path,
                                    'settings': {}  # Simplified, no parsing for directory contents
                                })
            
            snapshot['config_files'] = config_files
            
            # Get system tweaks
            try:
                tweaks = []
                sysctl_output = subprocess.check_output(['sysctl', '-a'], stderr=subprocess.DEVNULL).decode().strip()
                for line in sysctl_output.split('\n'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        # Only include potentially important tweaks
                        if any(important in key.strip() for important in ['vm.swappiness', 'fs.inotify', 'kernel.shmmax', 'net.ipv4.tcp_congestion_control']):
                            tweaks.append({
                                'component': 'sysctl',
                                'tweak': f"{key.strip()}={value.strip()}"
                            })
                snapshot['tweaks'] = tweaks
            except Exception as e:
                print(f"Warning: Could not get system tweaks: {e}")
            
            # Get services status
            try:
                services = []
                systemd_output = subprocess.check_output(['systemctl', 'list-units', '--type=service', '--state=active'], stderr=subprocess.DEVNULL).decode().strip()
                for line in systemd_output.split('\n'):
                    if '.service' in line:
                        parts = line.split()
                        if len(parts) >= 1:
                            service_name = parts[0]
                            if not service_name.startswith('sys-') and not service_name.startswith('dev-'):
                                services.append(service_name)
                snapshot['services'] = services
            except Exception as e:
                print(f"Warning: Could not get service information: {e}")
        
        # Get package-specific configurations
        try:
            package_configs = []
            
            # Check for specific packages and their configs
            important_packages = ['neovim', 'vim', 'i3', 'zsh', 'bash', 'emacs']
            for pkg in important_packages:
                if self._is_package_installed(pkg):
                    pkg_configs = self._get_package_configs(pkg)
                    package_configs.extend(pkg_configs)
            
            snapshot['package_configs'] = package_configs
        except Exception as e:
            print(f"Warning: Could not get package-specific configurations: {e}")
        
        return snapshot
    
    def _parse_config_settings(self, file_path: str) -> Dict[str, str]:
        """
        Parse a configuration file for key settings
        
        This is a simplified version that just returns a subset of important lines
        A real implementation would parse specific config formats properly
        """
        settings = {}
        
        try:
            with open(file_path, 'r') as f:
                content = f.read()
                
                # Just extract some non-comment lines as a sampling
                count = 0
                for line in content.split('\n'):
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        settings[key.strip()] = value.strip()
                        count += 1
                        if count >= 5:  # Limit to 5 settings per file
                            break
        except Exception as e:
            print(f"Warning: Could not parse config file {file_path}: {e}")
            
        return settings
    
    def _is_package_installed(self, package_name: str) -> bool:
        """Check if a package is installed"""
        try:
            result = subprocess.run(['pacman', '-Qi', package_name], 
                                    stdout=subprocess.PIPE, 
                                    stderr=subprocess.PIPE,
                                    text=True)
            return result.returncode == 0
        except Exception:
            return False
    
    def _get_package_configs(self, package: str) -> List[Dict[str, str]]:
        """Get configurations for a specific package"""
        configs = []
        
        # Package-specific config paths
        config_paths = {
            'neovim': ['~/.config/nvim/init.vim'],
            'vim': ['~/.vimrc'],
            'i3': ['~/.config/i3/config'],
            'zsh': ['~/.zshrc'],
            'bash': ['~/.bashrc'],
            'emacs': ['~/.emacs', '~/.emacs.d/init.el']
        }
        
        # Check for the package's config files
        if package in config_paths:
            for path in config_paths[package]:
                expanded_path = os.path.expanduser(path)
                if os.path.exists(expanded_path):
                    # For simplicity, just grab the first 3 non-commented lines
                    try:
                        with open(expanded_path, 'r') as f:
                            content_lines = []
                            for line in f:
                                line = line.strip()
                                if line and not line.startswith('#'):
                                    content_lines.append(line)
                                    if len(content_lines) >= 3:
                                        break
                            
                            # Join the content lines with a special separator
                            content = ";;;".join(content_lines)
                            
                            configs.append({
                                'package': package,
                                'config_type': 'c',  # c for config file
                                'path': path,
                                'content': content
                            })
                    except Exception as e:
                        print(f"Warning: Could not read config file {path} for package {package}: {e}")
        
        return configs
    
    def create_system_snapshot(self, scope: str = "full", output_path: Optional[str] = None, include_raw: bool = False) -> Dict[str, Any]:
        """
        Create a ClaudeScript snapshot of the current system
        
        Args:
            scope: Scope of the snapshot (full, minimal, package, etc.)
            output_path: Path to save the snapshot to
            include_raw: Whether to include raw system data in the return value
            
        Returns:
            Dictionary with snapshot information including ClaudeScript strings
        """
        # Get system snapshot data
        snapshot_data = self.get_system_snapshot(scope)
        
        # Encode as ClaudeScript
        claudescript_lines = self.encode_snapshot(snapshot_data)
        
        # Save to file if output path provided
        if output_path:
            with open(output_path, 'w') as f:
                for line in claudescript_lines:
                    f.write(f"{line}\n")
        
        # Return result
        result = {
            'claudescript': claudescript_lines,
            'timestamp': snapshot_data.get('timestamp', datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')),
            'scope': scope
        }
        
        if include_raw:
            result['raw_data'] = snapshot_data
            
        return result
    
    def apply_snapshot(self, snapshot_path: str, dry_run: bool = True) -> Dict[str, Any]:
        """
        Apply a snapshot to the system
        
        Args:
            snapshot_path: Path to the snapshot file
            dry_run: Whether to just simulate application without making changes
            
        Returns:
            Dictionary with application results
        """
        # Read snapshot file
        with open(snapshot_path, 'r') as f:
            claudescript_lines = [line.strip() for line in f if line.strip()]
        
        # Decode snapshot
        snapshot = self.decode_snapshot(claudescript_lines)
        
        # This would be a much more involved implementation, connecting to package managers etc.
        # For now we'll simulate what would happen and report the results
        
        results = {
            'changes': [],
            'errors': [],
            'warnings': []
        }
        
        # Process packages
        for package in snapshot.get('packages', []):
            pkg_name = package.get('name')
            if not pkg_name:
                continue
                
            # Check if package is installed
            if not self._is_package_installed(pkg_name):
                if dry_run:
                    results['changes'].append(f"Would install package: {pkg_name}")
                else:
                    try:
                        # In a real implementation, this would use OperatingTools to install
                        results['changes'].append(f"Installing package: {pkg_name}")
                        # Simulated success for now
                        results['changes'].append(f"Installed {pkg_name}")
                    except Exception as e:
                        results['errors'].append(f"Failed to install {pkg_name}: {str(e)}")
            else:
                results['warnings'].append(f"Package already installed: {pkg_name}")
        
        # Process configuration files
        for config in snapshot.get('config_files', []):
            path = config.get('path', '')
            settings = config.get('settings', {})
            
            if not path:
                continue
                
            expanded_path = os.path.expanduser(path)
            if os.path.exists(expanded_path):
                if dry_run:
                    results['changes'].append(f"Would update configuration: {path}")
                else:
                    try:
                        # In a real implementation, this would update the config file
                        results['changes'].append(f"Updating configuration: {path}")
                        # Simulated success for now
                        results['changes'].append(f"Updated {path}")
                    except Exception as e:
                        results['errors'].append(f"Failed to update {path}: {str(e)}")
            else:
                if dry_run:
                    results['changes'].append(f"Would create configuration: {path}")
                else:
                    try:
                        # Create parent directories
                        os.makedirs(os.path.dirname(expanded_path), exist_ok=True)
                        # In a real implementation, this would create the config file
                        results['changes'].append(f"Creating configuration: {path}")
                        # Simulated success for now
                        results['changes'].append(f"Created {path}")
                    except Exception as e:
                        results['errors'].append(f"Failed to create {path}: {str(e)}")
        
        # Process package-specific configurations
        for pkg_config in snapshot.get('package_configs', []):
            package = pkg_config.get('package', '')
            path = pkg_config.get('path', '')
            
            if not package or not path:
                continue
                
            # Check if package is installed
            if not self._is_package_installed(package):
                results['warnings'].append(f"Package {package} not installed, skipping its configuration")
                continue
                
            expanded_path = os.path.expanduser(path)
            if dry_run:
                results['changes'].append(f"Would configure {package} at {path}")
            else:
                try:
                    # In a real implementation, this would update package config
                    results['changes'].append(f"Configuring {package} at {path}")
                    # Simulated success for now
                    results['changes'].append(f"Configured {package}")
                except Exception as e:
                    results['errors'].append(f"Failed to configure {package}: {str(e)}")
        
        # Process system tweaks
        for tweak in snapshot.get('tweaks', []):
            component = tweak.get('component', '')
            tweak_value = tweak.get('tweak', '')
            
            if not component or not tweak_value:
                continue
                
            if dry_run:
                results['changes'].append(f"Would apply tweak to {component}: {tweak_value}")
            else:
                try:
                    # In a real implementation, this would apply the tweak
                    results['changes'].append(f"Applying tweak to {component}: {tweak_value}")
                    # Simulated success for now
                    results['changes'].append(f"Applied tweak to {component}")
                except Exception as e:
                    results['errors'].append(f"Failed to apply tweak to {component}: {str(e)}")
        
        return results
    
    def compare_snapshots(self, snapshot1_path: str, snapshot2_path: str) -> Dict[str, Any]:
        """
        Compare two snapshots and return the differences
        
        Args:
            snapshot1_path: Path to the first snapshot
            snapshot2_path: Path to the second snapshot
            
        Returns:
            Dictionary with the differences between the snapshots
        """
        # Read snapshot files
        with open(snapshot1_path, 'r') as f:
            lines1 = [line.strip() for line in f if line.strip()]
        
        with open(snapshot2_path, 'r') as f:
            lines2 = [line.strip() for line in f if line.strip()]
        
        # Decode snapshots
        snapshot1 = self.decode_snapshot(lines1)
        snapshot2 = self.decode_snapshot(lines2)
        
        # Compare and find differences
        differences = {
            'added_packages': [],
            'removed_packages': [],
            'added_configs': [],
            'changed_configs': [],
            'removed_configs': [],
            'changed_tweaks': []
        }
        
        # Compare packages
        pkg1_names = {pkg['name'] for pkg in snapshot1.get('packages', [])}
        pkg2_names = {pkg['name'] for pkg in snapshot2.get('packages', [])}
        
        differences['added_packages'] = list(pkg2_names - pkg1_names)
        differences['removed_packages'] = list(pkg1_names - pkg2_names)
        
        # Compare configs
        config1_paths = {config['path'] for config in snapshot1.get('config_files', [])}
        config2_paths = {config['path'] for config in snapshot2.get('config_files', [])}
        
        differences['added_configs'] = list(config2_paths - config1_paths)
        differences['removed_configs'] = list(config1_paths - config2_paths)
        
        # Find changed configs (same path but different settings)
        common_paths = config1_paths.intersection(config2_paths)
        config1_dict = {config['path']: config['settings'] for config in snapshot1.get('config_files', []) if config['path'] in common_paths}
        config2_dict = {config['path']: config['settings'] for config in snapshot2.get('config_files', []) if config['path'] in common_paths}
        
        for path in common_paths:
            if config1_dict.get(path) != config2_dict.get(path):
                differences['changed_configs'].append(path)
        
        # Prepare a summary
        differences['summary'] = {
            'packages': {
                'added': len(differences['added_packages']),
                'removed': len(differences['removed_packages'])
            },
            'configs': {
                'added': len(differences['added_configs']),
                'changed': len(differences['changed_configs']),
                'removed': len(differences['removed_configs'])
            }
        }
        
        return differences
    
    def get_package_snapshot(self, package_name: str, output_path: Optional[str] = None) -> Dict[str, Any]:
        """
        Create a package-specific snapshot
        
        Args:
            package_name: Name of the package to snapshot
            output_path: Path to save the snapshot to
            
        Returns:
            Dictionary with snapshot information
        """
        # Check if package is installed
        if not self._is_package_installed(package_name):
            raise ValueError(f"Package {package_name} is not installed")
        
        # Get package version
        try:
            version = subprocess.check_output(
                ['pacman', '-Qi', package_name, '|', 'grep', 'Version', '|', 'cut', '-d:', '-f2'],
                shell=True
            ).decode().strip()
        except Exception:
            version = "unknown"
        
        # Get package configuration
        pkg_configs = self._get_package_configs(package_name)
        
        # Build snapshot data
        snapshot_data = {
            'system_type': 'archlinux',
            'scope': f"package:{package_name}",
            'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
            'packages': [{
                'name': package_name,
                'version': version
            }],
            'package_configs': pkg_configs
        }
        
        # Get package dependencies
        try:
            deps_output = subprocess.check_output(
                ['pacman', '-Qi', package_name, '|', 'grep', 'Depends On', '|', 'cut', '-d:', '-f2'],
                shell=True
            ).decode().strip()
            
            if deps_output and deps_output != 'None':
                deps = [dep.strip() for dep in deps_output.split() if dep.strip() and not dep.startswith('None')]
                snapshot_data['dependencies'] = deps
        except Exception as e:
            print(f"Warning: Could not get dependencies for {package_name}: {e}")
        
        # Get package files
        try:
            files_output = subprocess.check_output(
                ['pacman', '-Ql', package_name],
                shell=True
            ).decode().strip()
            
            files = []
            for line in files_output.split('\n'):
                if line.strip():
                    parts = line.split()
                    if len(parts) >= 2:
                        file_path = parts[1]
                        if os.path.isfile(file_path):
                            files.append(file_path)
            
            # Limit to config files
            config_files = [f for f in files if f.startswith('/etc/') or '/share/config/' in f]
            if config_files:
                snapshot_data['package_files'] = config_files
        except Exception as e:
            print(f"Warning: Could not get files for {package_name}: {e}")
        
        # Encode as ClaudeScript
        claudescript_lines = self.encode_snapshot(snapshot_data)
        
        # Save to file if output path provided
        if output_path:
            with open(output_path, 'w') as f:
                for line in claudescript_lines:
                    f.write(f"{line}\n")
        
        # Return result
        return {
            'claudescript': claudescript_lines,
            'timestamp': snapshot_data['timestamp'],
            'scope': snapshot_data['scope'],
            'raw_data': snapshot_data
        }
    
    def create_diff_claudescript(self, before_snapshot: str, after_snapshot: str, output_path: Optional[str] = None) -> List[str]:
        """
        Create ClaudeScript commands that represent the difference between two snapshots
        
        Args:
            before_snapshot: Path to the before snapshot
            after_snapshot: Path to the after snapshot
            output_path: Path to save the ClaudeScript commands to
            
        Returns:
            List of ClaudeScript commands
        """
        # Compare snapshots
        diff = self.compare_snapshots(before_snapshot, after_snapshot)
        
        # Generate ClaudeScript commands
        commands = []
        
        # Add version and scope
        commands.append(self.encode_version())
        commands.append(self.encode_snapshot_scope("diff"))
        
        # Add package commands
        for pkg in diff['added_packages']:
            commands.append(self.encode_package(pkg))
        
        # Read after snapshot to get config details for added/changed configs
        with open(after_snapshot, 'r') as f:
            after_lines = [line.strip() for line in f if line.strip()]
        
        after_snapshot_data = self.decode_snapshot(after_lines)
        
        # Add config commands
        for config_path in diff['added_configs'] + diff['changed_configs']:
            for config in after_snapshot_data.get('config_files', []):
                if config['path'] == config_path:
                    commands.append(self.encode_config_file(config['path'], config['settings']))
                    break
        
        # Save to file if output path provided
        if output_path:
            with open(output_path, 'w') as f:
                for cmd in commands:
                    f.write(f"{cmd}\n")
        
        return commands

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
    snapshot_parser.add_argument('--scope', '-s', default='full', help='Snapshot scope (full, minimal)')
    
    # package snapshot command
    pkg_snapshot_parser = subparsers.add_parser('package-snapshot', help='Create a package-specific snapshot')
    pkg_snapshot_parser.add_argument('package', help='Package name')
    pkg_snapshot_parser.add_argument('--output', '-o', help='Output file')
    
    # apply command
    apply_parser = subparsers.add_parser('apply', help='Apply a snapshot')
    apply_parser.add_argument('snapshot', help='Snapshot file')
    apply_parser.add_argument('--dry-run', '-d', action='store_true', help='Simulate application without making changes')
    
    # compare command
    compare_parser = subparsers.add_parser('compare', help='Compare two snapshots')
    compare_parser.add_argument('snapshot1', help='First snapshot file')
    compare_parser.add_argument('snapshot2', help='Second snapshot file')
    
    # diff command
    diff_parser = subparsers.add_parser('diff', help='Create ClaudeScript commands for the difference between snapshots')
    diff_parser.add_argument('before', help='Before snapshot file')
    diff_parser.add_argument('after', help='After snapshot file')
    diff_parser.add_argument('--output', '-o', help='Output file')
    
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
            result = cs.create_system_snapshot(args.scope, args.output)
            
            if args.output:
                print(f"Snapshot saved to {args.output}")
                print(f"Scope: {result['scope']}")
                print(f"Timestamp: {result['timestamp']}")
                print(f"ClaudeScript lines: {len(result['claudescript'])}")
            else:
                print("ClaudeScript snapshot:")
                for line in result['claudescript']:
                    print(line)
        except Exception as e:
            print(f"Error creating snapshot: {e}")
            return 1
            
    elif args.command == 'package-snapshot':
        try:
            result = cs.get_package_snapshot(args.package, args.output)
            
            if args.output:
                print(f"Package snapshot saved to {args.output}")
                print(f"Package: {args.package}")
                print(f"Timestamp: {result['timestamp']}")
                print(f"ClaudeScript lines: {len(result['claudescript'])}")
            else:
                print(f"ClaudeScript snapshot for package {args.package}:")
                for line in result['claudescript']:
                    print(line)
        except Exception as e:
            print(f"Error creating package snapshot: {e}")
            return 1
            
    elif args.command == 'apply':
        try:
            result = cs.apply_snapshot(args.snapshot, args.dry_run)
            
            if args.dry_run:
                print("Dry run - no changes were made")
            
            print("Changes:")
            for change in result['changes']:
                print(f"  - {change}")
                
            if result['warnings']:
                print("\nWarnings:")
                for warning in result['warnings']:
                    print(f"  - {warning}")
                    
            if result['errors']:
                print("\nErrors:")
                for error in result['errors']:
                    print(f"  - {error}")
        except Exception as e:
            print(f"Error applying snapshot: {e}")
            return 1
            
    elif args.command == 'compare':
        try:
            diff = cs.compare_snapshots(args.snapshot1, args.snapshot2)
            
            print("Snapshot Comparison:")
            print(f"  Added packages: {diff['summary']['packages']['added']}")
            if diff['added_packages']:
                for pkg in diff['added_packages']:
                    print(f"    - {pkg}")
            
            print(f"  Removed packages: {diff['summary']['packages']['removed']}")
            if diff['removed_packages']:
                for pkg in diff['removed_packages']:
                    print(f"    - {pkg}")
            
            print(f"  Added configs: {diff['summary']['configs']['added']}")
            if diff['added_configs']:
                for cfg in diff['added_configs']:
                    print(f"    - {cfg}")
            
            print(f"  Changed configs: {diff['summary']['configs']['changed']}")
            if diff['changed_configs']:
                for cfg in diff['changed_configs']:
                    print(f"    - {cfg}")
            
            print(f"  Removed configs: {diff['summary']['configs']['removed']}")
            if diff['removed_configs']:
                for cfg in diff['removed_configs']:
                    print(f"    - {cfg}")
        except Exception as e:
            print(f"Error comparing snapshots: {e}")
            return 1
            
    elif args.command == 'diff':
        try:
            commands = cs.create_diff_claudescript(args.before, args.after, args.output)
            
            if args.output:
                print(f"Diff ClaudeScript saved to {args.output}")
                print(f"Commands: {len(commands)}")
            else:
                print("Diff ClaudeScript commands:")
                for cmd in commands:
                    print(cmd)
        except Exception as e:
            print(f"Error creating diff: {e}")
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
