#!/usr/bin/env python3
"""
CLI Interface for 7-Zip on macOS
Command-line interface for 7-Zip archive management
"""

import subprocess
import os
import sys
import time
from pathlib import Path
import argparse
import signal
import re
import select  # For non-blocking I/O
import json  # For preferences config file

class Colors:
    """ANSI color codes optimized for both light and dark terminals"""
    BLUE = '\033[34m'      # Dark blue - readable on both backgrounds
    GREEN = '\033[32m'     # Dark green - readable on both backgrounds  
    YELLOW = '\033[33m'    # Dark yellow/brown - better than bright yellow
    RED = '\033[31m'       # Dark red - readable on both backgrounds
    PURPLE = '\033[35m'    # Dark purple - readable on both backgrounds
    CYAN = '\033[36m'      # Dark cyan - readable on both backgrounds
    WHITE = '\033[37m'     # Standard white
    BOLD = '\033[1m'       # Bold text
    DIM = '\033[2m'        # Dimmed text
    DEFAULT = '\033[39m'   # System default - adapts to terminal
    END = '\033[0m'        # Reset all formatting

class SevenZipCLI:
    def __init__(self):
        # Initialize preferences first
        self.config_file = os.path.expanduser("~/.7zip_cli_preferences.json")
        self.preferences = self.load_preferences()
        
        # Try bundled 7-Zip first (included with project) - this is the primary method
        bundled_path = os.path.join(os.path.dirname(__file__), "7zz")
        
        # Fallback to standard installation paths if bundled version missing
        external_paths = [
            "/usr/local/bin/7zz",  # Homebrew installation
            "/opt/homebrew/bin/7zz",  # Apple Silicon Homebrew
            "/usr/local/bin/7z",   # Alternative Homebrew name
            "/opt/homebrew/bin/7z"  # Alternative Apple Silicon name
        ]
        
        if os.path.exists(bundled_path):
            self.seven_zip_path = bundled_path
        else:
            # Try external paths
            found_external = False
            for path in external_paths:
                if os.path.exists(path):
                    self.seven_zip_path = path
                    found_external = True
                    break
            
            if not found_external:
                self.seven_zip_path = "7zz"  # Try system PATH as final fallback
            
        self.progress_chars = ["|", "/", "-", "\\"]  # Simple ASCII spinner
        self.progress_index = 0
        
        # Resource management
        self.setup_resource_limits()
        self.setup_signal_handlers()
        self.caffeinate_process = None
    
    def load_preferences(self):
        """Load user preferences from config file"""
        default_preferences = {
            "compression_preset": "balanced",  # fast, balanced, maximum, custom
            "custom_compression_level": 5,
            "default_output_directory": os.path.expanduser("~/Desktop"),
            "auto_open_after_extract": False,
            "exclude_patterns": [".DS_Store", ".Thumbs.db", "Thumbs.db"],
            "remember_last_directory": True,
            "last_output_directory": os.path.expanduser("~/Desktop")
        }
        
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    loaded_prefs = json.load(f)
                    # Merge with defaults to handle new preferences
                    default_preferences.update(loaded_prefs)
            return default_preferences
        except (json.JSONDecodeError, IOError) as e:
            print(f"{Colors.YELLOW}Warning: Could not load preferences ({e}), using defaults{Colors.END}")
            return default_preferences
    
    def save_preferences(self):
        """Save current preferences to config file"""
        try:
            with open(self.config_file, 'w') as f:
                json.dump(self.preferences, f, indent=2)
        except IOError as e:
            print(f"{Colors.YELLOW}Warning: Could not save preferences: {e}{Colors.END}")
    
    def reset_preferences(self):
        """Reset all preferences to defaults"""
        if os.path.exists(self.config_file):
            os.remove(self.config_file)
        self.preferences = self.load_preferences()
        self.save_preferences()
        print(f"{Colors.GREEN}SUCCESS: Preferences reset to defaults{Colors.END}")
        
    def setup_resource_limits(self):
        """Set reasonable resource limits to prevent system overload"""
        try:
            # Set lower process priority to reduce system impact
            os.nice(5)  # Higher nice value = lower priority
            
            # Note: No CPU time limits - operations can run indefinitely
            
        except (OSError, ValueError) as e:
            # Some systems may not support all limits
            print(f"{Colors.YELLOW}WARNING: Could not set all resource limits: {e}{Colors.END}")
    
    def setup_signal_handlers(self):
        """Setup signal handlers for graceful cleanup"""
        def signal_handler(signum, frame):
            self.cleanup_and_exit()
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    def start_caffeinate(self):
        """Prevent system and display sleep during operations (with full disclosure)"""
        try:
            print(f"\n{Colors.YELLOW}SLEEP PREVENTION NOTICE:{Colors.END}")
            print(f"{Colors.CYAN}Large archive operations can take 30+ minutes and may fail if interrupted.{Colors.END}")
            print(f"{Colors.CYAN}We recommend preventing ALL sleep during the operation:{Colors.END}")
            print(f"{Colors.CYAN}• System sleep (prevents USB drive disconnection){Colors.END}")
            print(f"{Colors.CYAN}• Display sleep (prevents screen lock interruption){Colors.END}")
            print(f"{Colors.CYAN}• Prevents automatic process suspension{Colors.END}")
            print(f"\n{Colors.YELLOW}WARNING: YOUR COMPUTER WILL NOT SLEEP OR LOCK SCREEN DURING OPERATION{Colors.END}")
            
            prevent_sleep = input(f"{Colors.DEFAULT}Enable comprehensive sleep prevention? (y/n, default: n): {Colors.END}").lower()
            
            if prevent_sleep in ['y', 'yes']:  # Must explicitly say yes
                # Prevent both system sleep AND display sleep
                self.caffeinate_process = subprocess.Popen(
                    ['caffeinate', '-d', '-i', '-s'], 
                    stdout=subprocess.DEVNULL, 
                    stderr=subprocess.DEVNULL
                )
                print(f"{Colors.GREEN}SUCCESS: Complete sleep prevention active (system + display + idle){Colors.END}")
                print(f"{Colors.CYAN}Your computer will stay awake until the operation completes{Colors.END}")
                return True
            else:
                print(f"{Colors.YELLOW}WARNING: Sleep prevention disabled - operation may fail if system sleeps{Colors.END}")
                print(f"{Colors.CYAN}TIP: Keep your computer active and don't let it sleep during operation{Colors.END}")
                return False
        except Exception as e:
            print(f"{Colors.YELLOW}WARNING: Could not enable sleep prevention: {e}{Colors.END}")
            print(f"{Colors.CYAN}TIP: Please keep your computer active during the operation{Colors.END}")
            return False
    
    def stop_caffeinate(self):
        """Stop preventing system sleep"""
        if self.caffeinate_process:
            try:
                self.caffeinate_process.terminate()
                self.caffeinate_process.wait(timeout=5)
                self.caffeinate_process = None
                print(f"{Colors.CYAN}Sleep prevention stopped - normal power management restored{Colors.END}")
            except Exception as e:
                print(f"{Colors.YELLOW}WARNING: Error stopping sleep prevention: {e}{Colors.END}")
    
    def cleanup_and_exit(self):
        """Clean up resources before exit"""
        print(f"\n\n{Colors.YELLOW}Cleaning up...{Colors.END}")
        self.stop_caffeinate()
        print(f"{Colors.GREEN}Goodbye!{Colors.END}")
        sys.exit(0)
    
    def check_system_resources_before_operation(self, compression_level=5, total_size=0):
        """Check system resources before starting memory-intensive operations"""
        warnings = []
        
        try:
            # Check available memory using vm_stat (macOS) - CORRECTED VERSION
            vm_stat = subprocess.run(['vm_stat'], capture_output=True, text=True, timeout=5)
            if vm_stat.returncode == 0:
                lines = vm_stat.stdout.split('\n')
                free_pages = 0
                inactive_pages = 0
                speculative_pages = 0
                page_size = 16384  # Default for Apple Silicon
                
                for line in lines:
                    if 'page size of' in line:
                        page_size = int(line.split('of')[1].split('bytes')[0].strip())
                    elif 'Pages free:' in line:
                        free_pages = int(line.split(':')[1].strip().replace('.', ''))
                    elif 'Pages inactive:' in line:
                        inactive_pages = int(line.split(':')[1].strip().replace('.', ''))
                    elif 'Pages speculative:' in line:
                        speculative_pages = int(line.split(':')[1].strip().replace('.', ''))
                
                # Available memory = free + inactive + speculative (macOS can reclaim these)
                available_pages = free_pages + inactive_pages + speculative_pages
                available_memory_gb = (available_pages * page_size) / (1024**3)
                
                # Estimate memory usage for compression level
                memory_multiplier = {0: 0.1, 1: 0.2, 2: 0.5, 3: 1, 4: 2, 5: 3, 6: 5, 7: 8, 8: 12, 9: 16}
                estimated_memory_gb = memory_multiplier.get(compression_level, 3)
                
                if estimated_memory_gb > available_memory_gb:
                    warnings.append(f"Compression Level {compression_level} may need {estimated_memory_gb:.1f}GB but only {available_memory_gb:.1f}GB available")
                
                if available_memory_gb < 2:
                    warnings.append(f"Low system memory: Only {available_memory_gb:.1f}GB available")
        
        except Exception:
            # If we can't check memory, warn about high compression levels anyway
            if compression_level >= 8:
                warnings.append(f"Compression Level {compression_level} uses extreme amounts of memory")
        
        # Check CPU load
        try:
            load_avg = os.getloadavg()[0]
            cpu_count = os.cpu_count() or 1
            cpu_usage_percent = (load_avg / cpu_count) * 100
            
            if cpu_usage_percent > 70:
                warnings.append(f"High CPU load detected ({cpu_usage_percent:.1f}%)")
        except:
            pass
        
        # Display warnings if any
        if warnings:
            print(f"\n{Colors.RED}RESOURCE WARNINGS:{Colors.END}")
            for warning in warnings:
                print(f"{Colors.YELLOW}WARNING: {warning}{Colors.END}")
            
            print(f"\n{Colors.CYAN}TIP: Recommendations:{Colors.END}")
            print(f"{Colors.CYAN}• Close other applications to free memory{Colors.END}")
            print(f"{Colors.CYAN}• Use lower compression level (5 is recommended){Colors.END}")
            print(f"{Colors.CYAN}• Consider splitting large archives into smaller ones{Colors.END}")
            
            if compression_level >= 8:
                print(f"\n{Colors.RED}CRITICAL: Level {compression_level} can freeze your system!{Colors.END}")
                proceed = input(f"{Colors.DEFAULT}Continue anyway? (y/n, default: n): {Colors.END}").lower()
                return proceed == 'y'
            else:
                proceed = input(f"\n{Colors.DEFAULT}Continue with warnings? (y/n, default: n): {Colors.END}").lower()
                return proceed in ['y', 'yes']  # Must explicitly say yes
        
        return True
        """Basic system resource monitoring using built-in tools"""
        try:
            # Get CPU load average (1 minute)
            load_avg = os.getloadavg()[0]
            cpu_count = os.cpu_count() or 1
            cpu_usage_percent = (load_avg / cpu_count) * 100
            
            # Warn if system is under heavy load
            if cpu_usage_percent > 80:
                print(f"{Colors.YELLOW}WARNING: System CPU load is high ({cpu_usage_percent:.1f}%){Colors.END}")
                print(f"{Colors.CYAN}TIP: Consider closing other applications for better performance{Colors.END}")
            
        except Exception as e:
            # Silently fail if we can't monitor resources
            pass
        
    def print_header(self):
        """Display ASCII art banner"""
        banner = f"""{Colors.CYAN}
╔═══════════════════════════════════════════════════════════╗
║  ███████╗███████╗██╗██████╗      ██████╗██╗     ██╗       ║
║  ╚════██║╚════██║██║██╔══██╗    ██╔════╝██║     ██║       ║
║      ██╔╝    ██╔╝██║██████╔╝    ██║     ██║     ██║       ║
║     ██╔╝    ██╔╝ ██║██╔═══╝     ██║     ██║     ██║       ║
║    ██║     ██║   ██║██║         ╚██████╗███████╗██║       ║
║    ╚═╝     ╚═╝   ╚═╝╚═╝          ╚═════╝╚══════╝╚═╝       ║
╚═══════════════════════════════════════════════════════════╝{Colors.END}
{Colors.BOLD}{Colors.WHITE}          Command-Line Archive Tool{Colors.END}
{Colors.DIM}                    Powered by 7-Zip{Colors.END}
"""
        print(banner)
    
    def print_success(self, message):
        print(f"{Colors.GREEN}SUCCESS: {message}{Colors.END}")
    
    def print_error(self, message):
        print(f"{Colors.RED}ERROR: {message}{Colors.END}")
    
    def print_info(self, message):
        print(f"{Colors.CYAN}INFO: {message}{Colors.END}")
    
    def print_warning(self, message):
        print(f"{Colors.YELLOW}WARNING: {message}{Colors.END}")
    
    def show_progress(self, message="Working"):
        self.progress_index = (self.progress_index + 1) % len(self.progress_chars)
        char = self.progress_chars[self.progress_index]
        print(f"\r{Colors.YELLOW}{char} {message}...{Colors.END}", end="", flush=True)
    
    def clear_progress(self):
        print("\r" + " " * 50 + "\r", end="", flush=True)
    
    def check_7zip(self):
        if not os.path.exists(self.seven_zip_path):
            self.print_error(f"7-Zip not found at: {self.seven_zip_path}")
            return False
        
        try:
            result = subprocess.run([self.seven_zip_path], capture_output=True, timeout=5)
            return True
        except Exception as e:
            self.print_error(f"7-Zip check failed: {e}")
            return False
    
    def clean_macos_path(self, path):
        """Handle macOS drag-and-drop path escaping issues"""
        cleaned = path.strip().strip('"\'')
        
        # macOS Terminal escapes spaces and special chars when dragging
        # Try unescaping common patterns
        unescaped = cleaned.replace('\\ ', ' ').replace('\\(', '(').replace('\\)', ')').replace('\\&', '&')
        
        return cleaned, unescaped
    
    def get_file_paths(self, prompt="Enter file/folder paths"):
        print(f"\n{Colors.BOLD}{prompt}:{Colors.END}")
        print("• Drag and drop files/folders from Finder")
        print("• Or type paths separated by spaces")
        print("• Type 'cancel' to go back")
        print(f"{Colors.CYAN}TIP: For many files, add in batches or type 'file' to read from a text file{Colors.END}\n")
        
        all_files = []
        
        while True:
            try:
                paths_input = input(f"{Colors.DEFAULT}Path(s): {Colors.END}").strip()
                
                if paths_input.lower() == 'cancel':
                    return None
                
                # Special command to read from file
                if paths_input.lower() == 'file':
                    file_list_path = input(f"{Colors.DEFAULT}Path to text file with file list (one per line): {Colors.END}").strip()
                    if file_list_path.lower() == 'cancel':
                        return None
                    
                    try:
                        # Clean the path
                        _, cleaned_path = self.clean_macos_path(file_list_path)
                        if os.path.exists(cleaned_path):
                            with open(cleaned_path, 'r') as f:
                                file_paths = [line.strip() for line in f if line.strip()]
                                for path in file_paths:
                                    _, clean_path = self.clean_macos_path(path)
                                    if os.path.exists(clean_path):
                                        all_files.append(clean_path)
                                    else:
                                        self.print_warning(f"File not found (skipping): {path}")
                                
                                if all_files:
                                    self.print_success(f"Loaded {len(all_files)} files from list")
                                    break
                                else:
                                    self.print_warning("No valid files found in the file list")
                                    continue
                        else:
                            self.print_error(f"File list not found: {file_list_path}")
                            continue
                    except Exception as e:
                        self.print_error(f"Error reading file list: {e}")
                        continue
                    
                if not paths_input:
                    self.print_warning("Please enter at least one path")
                    continue
                
                # Check if input might be truncated (heuristic: very long + doesn't end cleanly)
                if len(paths_input) > 4000 and not paths_input.endswith((' ', '\t', '/')):
                    self.print_warning("⚠️  Input might be truncated! Terminal has a character limit.")
                    print(f"{Colors.CYAN}Suggestion: Add files in smaller batches, or type 'file' to load from a text file.{Colors.END}")
                    retry = input(f"{Colors.DEFAULT}Continue anyway? (y/n): {Colors.END}").strip().lower()
                    if retry not in ['y', 'yes']:
                        continue
                
                # Split by spaces but handle quoted paths
                import shlex
                try:
                    path_list = shlex.split(paths_input)
                except ValueError:
                    # If shlex fails, fall back to simple split
                    path_list = paths_input.split()
                
                valid_paths = []
                for path in path_list:
                    # Handle macOS drag-and-drop escaping
                    original_path, unescaped_path = self.clean_macos_path(path)
                    
                    # Try both versions
                    if os.path.exists(original_path):
                        valid_paths.append(original_path)
                    elif os.path.exists(unescaped_path):
                        valid_paths.append(unescaped_path)
                    else:
                        self.print_warning(f"File or folder not found: {original_path}")
                        if original_path != unescaped_path:
                            print(f"  {Colors.DIM}Also tried: {unescaped_path}{Colors.END}")
                        print(f"  {Colors.CYAN}TIP: Tip: Drag and drop from Finder, or check the path spelling{Colors.END}")
                
                if valid_paths:
                    all_files.extend(valid_paths)
                    if len(valid_paths) == 1:
                        self.print_success(f"Added: {os.path.basename(valid_paths[0])}")
                    else:
                        self.print_success(f"Added {len(valid_paths)} items: {', '.join(os.path.basename(p) for p in valid_paths[:3])}{'...' if len(valid_paths) > 3 else ''}")
                    
                    # Ask if they want to add more
                    add_more = input(f"{Colors.DEFAULT}Add more files? (y/n): {Colors.END}").strip().lower()
                    if add_more not in ['y', 'yes']:
                        break
                else:
                    self.print_warning("ERROR: No valid files found. Please check your paths and try again.")
                    
            except KeyboardInterrupt:
                print(f"\n{Colors.YELLOW}Operation cancelled by user{Colors.END}")
                return None
        
        return all_files if all_files else None
    
    def get_output_path(self, default_name="archive.7z", source_files=None):
        """Get output path with smart defaults based on user preferences and source content"""
        
        # Generate smart default name based on source files
        if source_files and len(source_files) > 0:
            smart_name = self.generate_smart_archive_name(source_files)
        else:
            smart_name = default_name
        
        # Determine default directory based on preferences
        if self.preferences.get("remember_last_directory", True) and "last_output_directory" in self.preferences:
            default_dir = self.preferences["last_output_directory"]
        else:
            default_dir = self.preferences.get("default_output_directory", os.path.expanduser("~/Desktop"))
        
        default_full_path = os.path.join(default_dir, smart_name)
        
        print(f"\n{Colors.BOLD}Output Archive Path:{Colors.END}")
        print(f"Smart suggestion: {default_full_path}")
        
        path = input(f"{Colors.DEFAULT}Path (or press Enter to use suggestion): {Colors.END}").strip()
        
        if not path:
            return default_full_path
        
        path = path.strip('"\'')
        
        # Handle macOS drag-and-drop escaping for output path too
        original_path, unescaped_path = self.clean_macos_path(path)
        
        # Use the unescaped version for processing
        path = unescaped_path
        
        # Check if user provided just a directory
        if os.path.isdir(path) or path.endswith('/'):
            # User gave directory only - need to create filename
            base_dir = path.rstrip('/')
            
            if len(source_files) == 1:
                # Single file: use its name
                base_name = os.path.splitext(os.path.basename(source_files[0]))[0]
                filename = f"{base_name}.7z"
                path = os.path.join(base_dir, filename)
                print(f"INFO: Using filename: {filename}")
            else:
                # Multiple files: ask for filename with smart default
                first_file_name = os.path.splitext(os.path.basename(source_files[0]))[0]
                default_filename = f"{first_file_name}_archive.7z"
                
                print(f"\nDirectory specified: {base_dir}")
                print(f"Smart filename: {default_filename}")
                filename = input(f"Filename (or press Enter to use smart filename): ").strip()
                
                if not filename:
                    filename = default_filename
                
                # Add extension if missing
                if not any(filename.endswith(ext) for ext in ['.7z', '.zip', '.tar', '.gz']):
                    filename += '.7z'
                
                path = os.path.join(base_dir, filename)
        else:
            # User provided full path - add extension if missing
            if not any(path.endswith(ext) for ext in ['.7z', '.zip', '.tar', '.gz']):
                path += '.7z'
        
        # Remember this directory for next time
        output_dir = os.path.dirname(path)
        if output_dir and os.path.exists(output_dir):
            self.preferences["last_output_directory"] = output_dir
            self.save_preferences()
        
        # Validate and create parent directory
        parent_dir = os.path.dirname(path)
        if parent_dir and not os.path.exists(parent_dir):
            try:
                os.makedirs(parent_dir, exist_ok=True)
                self.print_success(f"Created directory: {parent_dir}")
            except Exception as e:
                self.print_error(f"Cannot create directory {parent_dir}: {e}")
                self.print_info("Using default location as fallback")
                filename = os.path.basename(path)
                path = os.path.join(default_dir, filename)
        
        return path
    
    def validate_files_for_archiving(self, file_paths):
        """Validate and filter files for archiving with security checks"""
        validated_files = []
        
        for file_path in file_paths:
            if not file_path or not file_path.strip():
                continue
                
            # Handle macOS drag-and-drop escaping
            original_path, unescaped_path = self.clean_macos_path(file_path)
            
            # Try both versions
            abs_path = None
            if os.path.exists(original_path):
                abs_path = os.path.abspath(original_path)
            elif os.path.exists(unescaped_path):
                abs_path = os.path.abspath(unescaped_path)
            else:
                continue
                
            # Security validation - skip sensitive system files
            if abs_path.startswith('/System') or abs_path.startswith('/usr/bin') or abs_path.startswith('/private'):
                continue
            
            validated_files.append(abs_path)
        
        return validated_files
    
    def check_disk_space(self, output_path, estimated_size_mb=None):
        """Check available disk space before operations"""
        try:
            import shutil
            
            # Get available space in the target directory
            output_dir = os.path.dirname(output_path) or os.getcwd()
            free_bytes = shutil.disk_usage(output_dir).free
            free_mb = free_bytes / (1024 * 1024)
            free_gb = free_mb / 1024
            
            # If we have an estimated size, check if we have enough space
            if estimated_size_mb:
                # Add 20% buffer for safety
                required_mb = estimated_size_mb * 1.2
                
                if free_mb < required_mb:
                    print(f"\n{Colors.RED}WARNING: DISK SPACE WARNING:{Colors.END}")
                    print(f"{Colors.YELLOW}Required: ~{required_mb:.1f}MB{Colors.END}")
                    print(f"{Colors.YELLOW}Available: {free_mb:.1f}MB{Colors.END}")
                    print(f"{Colors.YELLOW}You may not have enough space for this operation{Colors.END}")
                    
                    continue_anyway = input(f"\n{Colors.DEFAULT}Continue anyway? (y/n): {Colors.END}").strip().lower()
                    if continue_anyway not in ['y', 'yes']:
                        return False
                
                elif free_mb < (required_mb * 2):
                    # Space is tight but should work
                    print(f"\n{Colors.YELLOW}Disk space notice: {free_gb:.1f}GB available{Colors.END}")
                    print(f"{Colors.CYAN}Operation should complete successfully{Colors.END}")
            
            else:
                # General space check without estimate
                if free_gb < 1.0:
                    print(f"\n{Colors.YELLOW}WARNING: Low disk space: {free_mb:.0f}MB available{Colors.END}")
                    print(f"{Colors.CYAN}Consider freeing up space before large operations{Colors.END}")
                
            return True
            
        except Exception as e:
            # If disk space check fails, don't block the operation
            print(f"{Colors.DIM}Note: Could not check disk space ({e}){Colors.END}")
            return True
    
    def estimate_archive_size(self, source_files, compression_level):
        """Estimate final archive size based on source files and compression level"""
        try:
            total_size = 0
            
            for source in source_files:
                if os.path.isfile(source):
                    total_size += os.path.getsize(source)
                elif os.path.isdir(source):
                    for root, dirs, files in os.walk(source):
                        for file in files:
                            try:
                                total_size += os.path.getsize(os.path.join(root, file))
                            except OSError:
                                pass
            
            total_mb = total_size / (1024 * 1024)
            
            # Estimate compression ratios based on level
            compression_ratios = {
                0: 1.0,    # Store - no compression
                1: 0.7,    # Fast - ~30% compression
                2: 0.65,   # 
                3: 0.6,    #
                4: 0.55,   #
                5: 0.5,    # Normal - ~50% compression
                6: 0.45,   #
                7: 0.4,    #
                8: 0.35,   #
                9: 0.3     # Ultra - ~70% compression
            }
            
            ratio = compression_ratios.get(compression_level, 0.5)
            estimated_mb = total_mb * ratio
            
            print(f"\n{Colors.CYAN}Size estimate: {total_mb:.1f}MB → ~{estimated_mb:.1f}MB after compression{Colors.END}")
            return estimated_mb
            
        except Exception:
            return None
    
    def generate_smart_archive_name(self, source_files):
        """Generate intelligent archive names based on source content"""
        from datetime import datetime
        
        if len(source_files) == 1:
            # Single file or folder - use its name
            source = source_files[0]
            base_name = os.path.basename(source.rstrip('/'))
            
            # If it's a folder, use folder name
            if os.path.isdir(source):
                return f"{base_name}.7z"
            else:
                # If it's a file, use filename without extension
                name_without_ext = os.path.splitext(base_name)[0]
                return f"{name_without_ext}_archive.7z"
        
        else:
            # Multiple files - try to find common theme
            file_names = [os.path.basename(f.rstrip('/')) for f in source_files]
            
            # Look for common patterns
            if any('photo' in name.lower() or 'img' in name.lower() or name.lower().endswith(('.jpg', '.png', '.gif', '.heic')) for name in file_names):
                base_name = "Photos"
            elif any('doc' in name.lower() or name.lower().endswith(('.pdf', '.txt', '.docx', '.pages')) for name in file_names):
                base_name = "Documents"  
            elif any('video' in name.lower() or 'movie' in name.lower() or name.lower().endswith(('.mp4', '.mov', '.avi')) for name in file_names):
                base_name = "Videos"
            elif any('music' in name.lower() or 'audio' in name.lower() or name.lower().endswith(('.mp3', '.m4a', '.wav')) for name in file_names):
                base_name = "Audio"
            elif any('project' in name.lower() or 'src' in name.lower() or 'code' in name.lower() for name in file_names):
                base_name = "Project"
            else:
                # Try to find a common parent directory
                common_parent = os.path.dirname(source_files[0])
                if common_parent and all(f.startswith(common_parent) for f in source_files):
                    base_name = os.path.basename(common_parent) or "Files"
                else:
                    base_name = "Mixed_Files"
            
            # Add date for organization
            date_str = datetime.now().strftime("%Y-%m-%d")
            return f"{base_name}_{date_str}.7z"
    
    def get_password(self, optional=True, for_extraction=False):
        import getpass
        
        if optional:
            if for_extraction:
                prompt_text = "Is this archive password protected? (y/n): "
            else:
                prompt_text = "Add password protection? (y/n): "
            
            add_password = input(f"{Colors.DEFAULT}{prompt_text}{Colors.END}").lower()
            if add_password != 'y':
                return None
        
        while True:
            try:
                password = getpass.getpass(f"{Colors.DEFAULT}Password: {Colors.END}")
                if not password and optional:
                    return None
                
                if len(password) < 4:
                    self.print_warning("Password should be at least 4 characters")
                    continue
                
                confirm = getpass.getpass(f"{Colors.DEFAULT}Confirm password: {Colors.END}")
                if password == confirm:
                    return password
                else:
                    self.print_error("Passwords don't match. Try again.")
                    
            except KeyboardInterrupt:
                return None
    
    def get_compression_level(self):
        """Get compression level based on user preferences"""
        preset = self.preferences.get("compression_preset", "balanced")
        
        # If user set a specific preference, use it
        if preset == "fast":
            print(f"{Colors.GREEN}Using saved preference: Fast (Level 1){Colors.END}")
            return 1
        elif preset == "balanced":
            print(f"{Colors.GREEN}Using saved preference: Balanced (Level 5){Colors.END}")
            return 5
        elif preset == "maximum":
            print(f"{Colors.GREEN}Using saved preference: Maximum (Level 9){Colors.END}")
            return self._confirm_level_9()
        elif preset == "custom":
            level = self.preferences.get("custom_compression_level", 5)
            print(f"{Colors.GREEN}Using saved preference: Custom (Level {level}){Colors.END}")
            if level == 9:
                return self._confirm_level_9()
            return level
        
        # If set to "ask" or no preference, show menu
        print(f"\n{Colors.BOLD}Compression Level:{Colors.END}")
        print("1. Fast (Level 1) - Quick compression, larger files")
        print("2. Balanced (Level 5) - Good compression, reasonable speed")
        print("3. Maximum (Level 9) - Best compression, slower")
        print("4. Custom Level (0-9) - Advanced users")
        
        print(f"\n{Colors.CYAN}Tip: Set your preference in User Preferences to skip this menu{Colors.END}")
        
        while True:
            choice = input(f"{Colors.DEFAULT}Choose preset (1-4, default 2): {Colors.END}").strip()
            
            if not choice or choice == "2":
                return 5
            elif choice == "1":
                return 1
            elif choice == "3":
                return self._confirm_level_9()
            elif choice == "4":
                return self._get_custom_level()
            else:
                self.print_warning("Please enter 1-4")
    
    def _confirm_level_9(self):
        """Confirm Level 9 compression with warnings"""
        print(f"\n{Colors.RED}ULTRA COMPRESSION WARNING:{Colors.END}")
        print(f"{Colors.YELLOW}Level 9 compression can use 10+ GB of RAM and be extremely slow!{Colors.END}")
        print(f"{Colors.YELLOW}Your system has limited memory and may become unresponsive.{Colors.END}")
        print(f"{Colors.CYAN}Recommendation: Use Level 5 instead (nearly identical compression){Colors.END}")
        
        confirm = input(f"\n{Colors.DEFAULT}Continue with Level 9 anyway? (y/n, default: n): {Colors.END}").lower()
        if confirm != 'y':
            print(f"{Colors.GREEN}Smart choice! Using Level 5 instead.{Colors.END}")
            return 5
        else:
            print(f"{Colors.YELLOW}WARNING: Proceeding with Level 9 - monitor system resources!{Colors.END}")
            return 9
    
    def _get_custom_level(self):
        """Get custom compression level from user"""
        print(f"\n{Colors.BOLD}Custom Compression Level:{Colors.END}")
        print("0 - Store (no compression)")
        print("1 - Fastest")
        print("5 - Normal (recommended)")
        print("9 - Ultra")
        
        while True:
            level = input(f"{Colors.DEFAULT}Choose level (0-9): {Colors.END}").strip()
            
            try:
                level = int(level)
                if 0 <= level <= 9:
                    if level == 9:
                        return self._confirm_level_9()
                    elif level >= 7:
                        print(f"{Colors.YELLOW}WARNING: Level {level} uses significant memory and time{Colors.END}")
                    return level
                else:
                    self.print_warning("Please enter a number between 0 and 9")
            except ValueError:
                self.print_warning("Please enter a valid number")
    
    def format_size(self, size_bytes):
        """Format file size for display"""
        if size_bytes < 1024**2:
            return f"{size_bytes / 1024:.1f}KB"
        elif size_bytes < 1024**3:
            return f"{size_bytes / (1024**2):.1f}MB"
        else:
            return f"{size_bytes / (1024**3):.1f}GB"
    

    def create_archive(self):
        print(f"\n{Colors.PURPLE}{'─'*50}{Colors.END}")
        print(f"{Colors.BOLD}CREATE ARCHIVE{Colors.END}")
        print(f"{Colors.PURPLE}{'─'*50}{Colors.END}")
        
        files = self.get_file_paths("Files/Folders to Archive")
        if not files:
            self.print_warning("No files selected")
            return
        
        # Security: Validate file paths to prevent path traversal
        validated_files = self.validate_files_for_archiving(files)
        
        if not validated_files:
            self.print_error("No valid files to archive after security validation")
            return
        
        output_path = self.get_output_path(source_files=validated_files)
        
        # Check if output file already exists
        overwrite_existing = False
        if os.path.exists(output_path):
            print(f"\n{Colors.YELLOW}WARNING: File already exists: {os.path.basename(output_path)}{Colors.END}")
            print(f"{Colors.CYAN}Options:{Colors.END}")
            print(f"{Colors.CYAN}1. Overwrite existing file{Colors.END}")
            print(f"{Colors.CYAN}2. Choose a different filename{Colors.END}")
            print(f"{Colors.CYAN}3. Cancel operation{Colors.END}")
            
            choice = input(f"\n{Colors.DEFAULT}Choose option (1-3): {Colors.END}").strip()
            
            if choice == "2":
                output_path = self.get_output_path()
                if os.path.exists(output_path):
                    self.print_warning("File still exists. Please choose a different name.")
                    return
            elif choice == "3":
                self.print_warning("Operation cancelled")
                return
            elif choice == "1":
                overwrite_existing = True
            else:
                self.print_warning("Invalid choice. Operation cancelled.")
                return
        
        # Security: Validate output path
        output_abs = os.path.abspath(output_path)
        if output_abs.startswith('/System') or output_abs.startswith('/usr/bin'):
            self.print_error("Cannot create archives in system directories")
            return
        
        # Determine format from output path extension for format-specific handling
        output_ext = os.path.splitext(output_path)[1].lower().lstrip('.')
        
        # Warn about TAR password limitation before asking for password
        if output_ext == "tar":
            self.print_warning("Note: TAR format does not support password protection.")
            self.print_info("The archive will be created without encryption.")
            password = None
        else:
            password = self.get_password(optional=True)
        
        compression_level = self.get_compression_level()
        
        # Estimate archive size and check disk space
        estimated_size_mb = self.estimate_archive_size(validated_files, compression_level)
        if not self.check_disk_space(output_path, estimated_size_mb):
            self.print_info("Operation cancelled due to disk space concerns")
            return
        
        # Calculate total size for splitting decision
        total_size = 0
        try:
            for file_path in validated_files:
                if os.path.isfile(file_path):
                    total_size += os.path.getsize(file_path)
                elif os.path.isdir(file_path):
                    for root, dirs, files in os.walk(file_path):
                        for file in files:
                            try:
                                total_size += os.path.getsize(os.path.join(root, file))
                            except OSError:
                                pass
        except Exception:
            total_size = 0  # If calculation fails, disable splitting
        
        # Archive splitting option for large operations
        split_size = None
        if total_size > 10 * 1024 * 1024 * 1024:  # > 10GB
            print(f"\n{Colors.YELLOW}LARGE ARCHIVE DETECTED ({self.format_size(total_size)}){Colors.END}")
            print(f"{Colors.CYAN}Consider splitting into smaller parts for reliability:{Colors.END}")
            print(f"{Colors.CYAN}1. Single file (may fail on large operations){Colors.END}")
            print(f"{Colors.CYAN}2. Split into 4GB parts (recommended for large archives){Colors.END}")
            print(f"{Colors.CYAN}3. Split into 2GB parts (maximum compatibility){Colors.END}")
            print(f"{Colors.CYAN}4. Custom split size{Colors.END}")
            
            while True:
                choice = input(f"{Colors.DEFAULT}Choose option (1-4, default 1): {Colors.END}").strip()
                
                if not choice or choice == "1":
                    break
                elif choice == "2":
                    split_size = "4000m"
                    break
                elif choice == "3":
                    split_size = "2000m"
                    break
                elif choice == "4":
                    custom_size = input(f"{Colors.DEFAULT}Enter split size (e.g., 1000m, 500m): {Colors.END}").strip()
                    if custom_size:
                        split_size = custom_size
                        break
                else:
                    print(f"{Colors.RED}Invalid choice. Please enter 1-4.{Colors.END}")
        
        print(f"\n{Colors.BOLD}Summary:{Colors.END}")
        print(f"Files: {len(validated_files)}")
        print(f"Output: {os.path.basename(output_path)}")
        print(f"Password: {'Yes (AES-256)' if password else 'No'}")
        print(f"Compression: Level {compression_level}")
        if split_size:
            print(f"Split size: {split_size} (will create multiple files)")
        
        if not password:
            print(f"{Colors.YELLOW}WARNING: Archive will be unencrypted - consider adding a password{Colors.END}")
        if split_size:
            base_name = os.path.splitext(os.path.basename(output_path))[0]
            print(f"{Colors.CYAN}Split archives will be created as:{Colors.END}")
            print(f"   {base_name}.7z.001, {base_name}.7z.002, {base_name}.7z.003, etc.")
            print(f"   {Colors.DIM}Each part will be ~{split_size} in size{Colors.END}")
        
        # Calculate total size for resource estimation
        total_size = 0
        try:
            for file_path in validated_files:
                if os.path.isfile(file_path):
                    total_size += os.path.getsize(file_path)
                elif os.path.isdir(file_path):
                    for root, dirs, files in os.walk(file_path):
                        for file in files:
                            try:
                                total_size += os.path.getsize(os.path.join(root, file))
                            except:
                                pass
        except:
            pass
        
        # Check system resources before proceeding
        if not self.check_system_resources_before_operation(compression_level, total_size):
            self.print_warning("Operation cancelled due to resource concerns")
            return
        
        confirm = input(f"\n{Colors.DEFAULT}Create archive? (y/n): {Colors.END}").lower()
        if confirm != 'y':
            return
        
        # Build secure command with format-specific handling
        cmd = [self.seven_zip_path, "a"]
        
        # Compression level handling based on format
        # TAR doesn't support compression (it's just an archiver)
        if output_ext != "tar":
            cmd.append(f"-mx{compression_level}")
        
        # Add archive splitting if specified
        if split_size:
            cmd.append(f"-v{split_size}")
        
        # Add overwrite flag only if user explicitly chose to overwrite
        if overwrite_existing:
            cmd.append("-y")
        
        # Password handling based on format
        # Note: TAR check already done above, so password won't be set for TAR
        if password:
            cmd.append(f"-p{password}")
            # Header encryption only supported for 7z format
            if output_ext == "7z":
                cmd.append("-mhe=on")
        
        cmd.append(output_path)
        cmd.extend(validated_files)
        
        print(f"\n{Colors.CYAN}Running archive creation command...{Colors.END}")
        
        try:
            # Run 7-Zip with proper error handling
            result = subprocess.run(cmd, capture_output=False, text=True, check=False)
            
            # Check if 7-Zip encountered an error
            if result.returncode != 0:
                self.print_error(f"Archive creation failed (error code: {result.returncode})")
                self.print_error("This could be due to:")
                self.print_error("• Insufficient disk space")
                self.print_error("• Permission issues")
                self.print_error("• Invalid file paths")
                self.print_error("• Corrupted source files")
                return
            
        except Exception as e:
            self.print_error(f"Archive creation failed: {e}")
            return
        
        # Show completion info if archive was created successfully
        if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
            self.show_archive_completion(output_path, validated_files)
    
    def show_archive_completion(self, archive_path, source_files):
        """Show detailed completion information for archive creation"""
        if not os.path.exists(archive_path):
            self.print_error("Archive file not found after creation")
            return
        
        # Calculate sizes
        archive_size = os.path.getsize(archive_path)
        
        # Calculate total source size
        total_source_size = 0
        file_count = 0
        for source in source_files:
            if os.path.isfile(source):
                total_source_size += os.path.getsize(source)
                file_count += 1
            elif os.path.isdir(source):
                for root, dirs, files in os.walk(source):
                    for file in files:
                        try:
                            total_source_size += os.path.getsize(os.path.join(root, file))
                            file_count += 1
                        except OSError:
                            pass
        
        # Format sizes
        archive_mb = archive_size / (1024 * 1024)
        source_mb = total_source_size / (1024 * 1024)
        
        # Calculate compression ratio
        if total_source_size > 0:
            compression_ratio = ((total_source_size - archive_size) / total_source_size) * 100
            ratio_text = f" ({compression_ratio:.1f}% smaller)"
        else:
            ratio_text = ""
        
        print(f"\n{Colors.GREEN}Archive created successfully!{Colors.END}")
        print(f"{Colors.CYAN}Archive: {archive_path}{Colors.END}")
        print(f"{Colors.CYAN}Size: {source_mb:.1f}MB → {archive_mb:.1f}MB{ratio_text}{Colors.END}")
        print(f"{Colors.CYAN}Files: {file_count} processed{Colors.END}")
        
        # Offer to open containing folder
        try:
            archive_dir = os.path.dirname(archive_path)
            open_folder = input(f"\n{Colors.DEFAULT}Open containing folder? (y/n): {Colors.END}").strip().lower()
            if open_folder in ['y', 'yes']:
                subprocess.run(["open", archive_dir], check=True)
                print(f"{Colors.CYAN}FOLDER: Opened folder: {archive_dir}{Colors.END}")
        except (subprocess.CalledProcessError, KeyboardInterrupt):
            pass  # Gracefully handle if folder can't be opened or user cancels
    
    def get_archive_contents(self, archive_path, password=None):
        """Get list of files in archive for selective extraction"""
        cmd = [self.seven_zip_path, "l", archive_path, "-slt"]  # -slt for technical listing
        
        if password:
            cmd.append(f"-p{password}")
        
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)  # 5 minutes for large archives
            if result.returncode == 0:
                files = []
                current_file = {}
                
                for line in result.stdout.split('\n'):
                    line = line.strip()
                    if line.startswith('Path = '):
                        if current_file.get('path'):
                            files.append(current_file)
                        current_file = {'path': line[7:]}
                    elif line.startswith('Size = '):
                        current_file['size'] = int(line[7:]) if line[7:].isdigit() else 0
                    elif line.startswith('Folder = '):
                        current_file['is_folder'] = line[9:] == '+'
                
                if current_file.get('path'):
                    files.append(current_file)
                
                return True, files
            else:
                return False, result.stderr
        except Exception as e:
            return False, str(e)
    
    def select_files_for_extraction(self, files):
        """Interactive file selection for extraction"""
        if not files:
            return []
        
        print(f"\n{Colors.BOLD}SELECT FILES TO EXTRACT:{Colors.END}")
        print(f"{Colors.CYAN}Available files in archive:{Colors.END}")
        print(f"{Colors.BLUE}{'─'*60}{Colors.END}")
        
        # Display files with numbers
        for i, file_info in enumerate(files, 1):
            size_str = ""
            if not file_info.get('is_folder', False) and file_info.get('size', 0) > 0:
                size_mb = file_info['size'] / (1024 * 1024)
                if size_mb > 1:
                    size_str = f" ({size_mb:.1f} MB)"
                else:
                    size_kb = file_info['size'] / 1024
                    size_str = f" ({size_kb:.1f} KB)"
            
            folder_icon = "FOLDER" if file_info.get('is_folder', False) else "FILE"
            print(f"{Colors.DEFAULT}{i:3d}. {folder_icon} {file_info['path']}{size_str}{Colors.END}")
        
        print(f"\n{Colors.BOLD}Selection Options:{Colors.END}")
        print("• Enter numbers separated by spaces (e.g., 1 3 5)")
        print("• Enter ranges with dash (e.g., 1-5 8 10-12)")
        print("• Type 'all' to extract everything")
        print("• Type 'cancel' to go back")
        
        while True:
            selection = input(f"\n{Colors.DEFAULT}Select files: {Colors.END}").strip()
            
            if selection.lower() == 'cancel':
                return None
            elif selection.lower() == 'all':
                return [f['path'] for f in files]
            elif not selection:
                self.print_warning("Please enter your selection")
                continue
            
            try:
                selected_indices = set()
                parts = selection.split()
                
                for part in parts:
                    if '-' in part:
                        # Handle ranges like "1-5"
                        start, end = map(int, part.split('-'))
                        selected_indices.update(range(start, end + 1))
                    else:
                        # Handle single numbers
                        selected_indices.add(int(part))
                
                # Validate indices
                valid_indices = [i for i in selected_indices if 1 <= i <= len(files)]
                if not valid_indices:
                    self.print_warning("No valid file numbers entered")
                    continue
                
                selected_files = [files[i-1]['path'] for i in valid_indices]
                
                print(f"\n{Colors.GREEN}Selected {len(selected_files)} file(s):{Colors.END}")
                for file_path in selected_files:
                    print(f"  FILE {file_path}")
                
                confirm = input(f"\n{Colors.DEFAULT}Proceed with these files? (y/n): {Colors.END}").lower()
                if confirm == 'y':
                    return selected_files
                    
            except ValueError:
                self.print_warning("Invalid format. Use numbers, ranges (1-5), or 'all'")
    
    def extract_archive(self):
        print(f"\n{Colors.PURPLE}{'─'*50}{Colors.END}")
        print(f"{Colors.BOLD}EXTRACT ARCHIVE{Colors.END}")
        print(f"{Colors.PURPLE}{'─'*50}{Colors.END}")
        
        archive_input = input(f"{Colors.DEFAULT}Archive path(s) (separate multiple with spaces or newlines): {Colors.END}").strip()
        if not archive_input:
            self.print_error("No archive path provided")
            return
        
        # Split input by spaces and newlines to support multiple archives
        archive_paths_raw = archive_input.replace('\n', ' ').split()
        
        # Clean and validate all archive paths
        archive_paths = []
        for path_input in archive_paths_raw:
            original_path, unescaped_path = self.clean_macos_path(path_input)
            
            # Try both versions to find the archive
            if os.path.exists(original_path):
                archive_paths.append(original_path)
            elif os.path.exists(unescaped_path):
                archive_paths.append(unescaped_path)
            else:
                self.print_warning(f"Archive file not found (skipping): {original_path}")
        
        if not archive_paths:
            self.print_error("No valid archive files found")
            return
        
        print(f"\n{Colors.GREEN}Found {len(archive_paths)} archive(s) to extract{Colors.END}")
        for i, path in enumerate(archive_paths, 1):
            print(f"  {i}. {os.path.basename(path)}")
        
        # If multiple archives, ask about extraction mode
        extraction_mode = "separate"  # default
        if len(archive_paths) > 1:
            print(f"\n{Colors.BOLD}Multiple Archives Extraction Mode:{Colors.END}")
            print("1. Separate folders (each archive in its own folder) - RECOMMENDED")
            print("2. Combined (all archives to same destination)")
            
            mode_choice = input(f"{Colors.DEFAULT}Choose option (1-2, default 1): {Colors.END}").strip()
            extraction_mode = "combined" if mode_choice == "2" else "separate"
        
        # Selective extraction option (only for single archive)
        selected_files = []
        if len(archive_paths) == 1:
            print(f"\n{Colors.BOLD}Extraction Options:{Colors.END}")
            print("1. Extract all files (default)")
            print("2. Select specific files to extract")
            
            choice = input(f"{Colors.DEFAULT}Choose option (1-2, default 1): {Colors.END}").strip()
            
            if choice == "2":
                # Show simple file listing for selection
                print(f"\n{Colors.CYAN}Showing archive contents...{Colors.END}")
                print("(7-Zip will show contents and may ask for password if needed)")
                subprocess.run([self.seven_zip_path, "l", archive_paths[0]])
                
                # Let user specify files/patterns
                print(f"\n{Colors.BOLD}Enter files to extract:{Colors.END}")
                print("• Enter exact filenames separated by spaces")
                print("• Use patterns like *.txt or folder/* if needed")
                print("• Type 'cancel' to go back")
                
                file_input = input(f"\n{Colors.DEFAULT}Files to extract: {Colors.END}").strip()
                if file_input.lower() == 'cancel' or not file_input:
                    return
                    
                selected_files = file_input.split()
        
        # Get extraction destination
        default_extract = os.path.join(os.path.dirname(archive_paths[0]), "extracted")
        extract_input = input(f"\n{Colors.DEFAULT}Extract to (default: {default_extract}): {Colors.END}").strip()
        
        if not extract_input:
            extract_to = default_extract
        else:
            # Handle escaping for extract path too
            _, extract_to = self.clean_macos_path(extract_input)
        
        # Create extraction directory
        try:
            os.makedirs(extract_to, exist_ok=True)
        except Exception as e:
            self.print_error(f"Cannot create extraction directory: {e}")
            return
        
        # Check for existing files and offer resume options
        overwrite_flag = None
        if os.path.exists(extract_to) and os.listdir(extract_to):
            print(f"\n{Colors.YELLOW}WARNING: Destination folder already contains files{Colors.END}")
            print(f"\n{Colors.BOLD}Extraction Mode:{Colors.END}")
            print("1. Skip existing files (resume extraction)")
            print("2. Overwrite all files (restart extraction)")
            print("3. Ask for each file conflict")
            print("4. Cancel extraction")
            
            resume_choice = input(f"{Colors.DEFAULT}Choose option (1-4, default 1): {Colors.END}").strip()
            
            if resume_choice == "4":
                self.print_info("Extraction cancelled")
                return
            elif resume_choice == "2":
                overwrite_flag = "-aoa"  # Overwrite all
                print(f"{Colors.YELLOW}Will overwrite existing files{Colors.END}")
            elif resume_choice == "3":
                overwrite_flag = "-ao"   # Ask for each
                print(f"{Colors.CYAN}Will prompt for each file conflict{Colors.END}")
            else:
                overwrite_flag = "-aos"  # Skip existing (resume)
                print(f"{Colors.GREEN}Will skip existing files (resume mode){Colors.END}")
        
        print(f"\n{Colors.BOLD}Summary:{Colors.END}")
        print(f"Archives: {len(archive_paths)}")
        for path in archive_paths:
            print(f"  • {os.path.basename(path)}")
        print(f"Extract to: {extract_to}")
        if len(archive_paths) > 1:
            print(f"Mode: {extraction_mode.title()} folders")
        if selected_files:
            print(f"Files to extract: {len(selected_files)} selected files")
        else:
            print(f"Files to extract: All files in archive(s)")
        
        confirm = input(f"\n{Colors.DEFAULT}Extract archive(s)? (y/n): {Colors.END}").lower()
        if confirm != 'y':
            return
        
        # Extract all archives
        success_count = 0
        failed_archives = []
        
        for idx, archive_path in enumerate(archive_paths, 1):
            archive_name = os.path.basename(archive_path)
            archive_base = os.path.splitext(archive_name)[0]
            
            # Determine destination for this archive
            if extraction_mode == "separate" and len(archive_paths) > 1:
                current_dest = os.path.join(extract_to, archive_base)
                try:
                    os.makedirs(current_dest, exist_ok=True)
                except Exception as e:
                    self.print_error(f"Cannot create directory for {archive_name}: {e}")
                    failed_archives.append((archive_name, str(e)))
                    continue
            else:
                current_dest = extract_to
            
            print(f"\n{Colors.CYAN}[{idx}/{len(archive_paths)}] Extracting: {archive_name}{Colors.END}")
            
            # Build extraction command  
            cmd = [self.seven_zip_path, "x", archive_path, f"-o{current_dest}", "-y"]
            
            # Add overwrite flag if specified
            if overwrite_flag:
                cmd.append(overwrite_flag)
                
            # Add selected files if any (only for single archive)
            if selected_files and len(archive_paths) == 1:
                cmd.extend(selected_files)
            
            try:
                # Run 7-Zip with proper error handling
                result = subprocess.run(cmd, capture_output=False, text=True, check=False)
                
                # Check if 7-Zip encountered an error
                if result.returncode != 0:
                    self.print_error(f"Extraction failed for {archive_name} (error code: {result.returncode})")
                    failed_archives.append((archive_name, f"error code {result.returncode}"))
                else:
                    success_count += 1
                    self.print_success(f"✓ Extracted: {archive_name}")
                    
            except Exception as e:
                self.print_error(f"Extraction failed for {archive_name}: {e}")
                failed_archives.append((archive_name, str(e)))
        
        # Print summary
        print(f"\n{Colors.PURPLE}{'─'*50}{Colors.END}")
        print(f"{Colors.BOLD}EXTRACTION COMPLETE{Colors.END}")
        print(f"{Colors.PURPLE}{'─'*50}{Colors.END}")
        
        if success_count == len(archive_paths):
            self.print_success(f"All {success_count} archive(s) extracted successfully!")
        elif success_count > 0:
            self.print_warning(f"{success_count} of {len(archive_paths)} archive(s) extracted successfully")
            if failed_archives:
                print(f"\n{Colors.BOLD}Failed archives:{Colors.END}")
                for name, error in failed_archives:
                    print(f"  • {name}: {error}")
        else:
            self.print_error("All archives failed to extract")
            if failed_archives:
                print(f"\n{Colors.BOLD}Errors:{Colors.END}")
                for name, error in failed_archives:
                    print(f"  • {name}: {error}")
                print(f"\n{Colors.YELLOW}Common causes:{Colors.END}")
                print("• Corrupted or damaged archives")
                print("• Incorrect password")
                print("• Insufficient disk space")
                print("• Permission issues")
            return
        
        # Auto-open functionality (check if extraction succeeded by seeing if files exist)
        if success_count > 0 and os.path.exists(extract_to) and os.listdir(extract_to):
            self.handle_auto_open(extract_to)
    
    def handle_auto_open(self, directory_path):
        """Handle auto-opening of directories after extraction"""
        if not os.path.exists(directory_path):
            return
        
        # Check user preference
        if self.preferences.get("auto_open_after_extract", False):
            # Auto-open is enabled, open immediately
            try:
                subprocess.run(["open", directory_path], check=True)
                print(f"{Colors.CYAN}FOLDER: Opened folder: {directory_path}{Colors.END}")
            except subprocess.CalledProcessError:
                print(f"{Colors.YELLOW}WARNING: Could not auto-open folder{Colors.END}")
        else:
            # Ask user if they want to open
            try:
                open_folder = input(f"\n{Colors.DEFAULT}Open containing folder? (y/n): {Colors.END}").strip().lower()
                if open_folder in ['y', 'yes']:
                    subprocess.run(["open", directory_path], check=True)
                    print(f"{Colors.CYAN}FOLDER: Opened folder: {directory_path}{Colors.END}")
            except (subprocess.CalledProcessError, KeyboardInterrupt):
                pass  # Gracefully handle if folder can't be opened or user cancels
    
    def view_archive(self):
        print(f"\n{Colors.PURPLE}{'─'*50}{Colors.END}")
        print(f"{Colors.BOLD}VIEW ARCHIVE CONTENTS{Colors.END}")
        print(f"{Colors.PURPLE}{'─'*50}{Colors.END}")
        
        archive_input = input(f"{Colors.DEFAULT}Archive path: {Colors.END}").strip()
        if not archive_input:
            self.print_error("No archive path provided")
            return
        
        # Handle macOS drag-and-drop escaping
        original_path, unescaped_path = self.clean_macos_path(archive_input)
        
        # Try both versions to find the archive
        archive_path = None
        if os.path.exists(original_path):
            archive_path = original_path
        elif os.path.exists(unescaped_path):
            archive_path = unescaped_path
        
        if not archive_path:
            self.print_error(f"Archive file not found: {original_path}")
            if original_path != unescaped_path:
                print(f"  Also tried: {unescaped_path}")
            return
        
        print(f"\n{Colors.BOLD}Archive Operations:{Colors.END}")
        print("1. List contents (basic)")
        print("2. List contents (detailed)")
        print("3. Test archive integrity") 
        print("4. Archive technical info")
        
        choice = input(f"{Colors.DEFAULT}Choose option (1-4, default 1): {Colors.END}").strip()
        
        # Build 7-Zip command based on choice
        if choice == "3":
            cmd = [self.seven_zip_path, "t", archive_path]  # test integrity
        elif choice == "4":
            cmd = [self.seven_zip_path, "i", archive_path]  # technical info
        elif choice == "2":
            cmd = [self.seven_zip_path, "l", "-slt", archive_path]  # detailed listing
        else:
            cmd = [self.seven_zip_path, "l", archive_path]  # basic listing
        
        print(f"\n{Colors.CYAN}Running 7-Zip command...{Colors.END}")
        
        # Pure passthrough - let 7-Zip handle passwords and everything
        subprocess.run(cmd)
    

    def show_help(self):
        """Show comprehensive help and tips"""
        print(f"\n{Colors.PURPLE}{'─'*60}{Colors.END}")
        print(f"{Colors.BOLD}HELP & TIPS{Colors.END}")
        print(f"{Colors.PURPLE}{'─'*60}{Colors.END}")
        
        print(f"\n{Colors.BOLD}Help Topics:{Colors.END}")
        print("1. Quick Start Guide")
        print("2. Archive Formats & Compression")
        print("3. File Input Methods")
        print("4. User Preferences & Settings")
        print("5. Advanced Features")
        print("6. Troubleshooting")
        print("7. Show All Help")
        print("8. Back to Main Menu")
        
        choice = input(f"\n{Colors.DEFAULT}Choose topic (1-8): {Colors.END}").strip()
        
        if choice == "1":
            self.show_quick_start()
        elif choice == "2":
            self.show_compression_help()
        elif choice == "3":
            self.show_input_help()
        elif choice == "4":
            self.show_preferences_help()
        elif choice == "5":
            self.show_advanced_help()
        elif choice == "6":
            self.show_troubleshooting()
        elif choice == "7":
            self.show_all_help()
        elif choice == "8":
            return  # Exit directly without prompt
        else:
            self.print_warning("Invalid choice. Please enter 1-8.")
            input(f"\n{Colors.DEFAULT}Press Enter to return to help menu...{Colors.END}")
            self.show_help()  # Return to help menu
            return
        
        # After showing help topic (choices 1-7), ask to continue
        input(f"\n{Colors.DEFAULT}Press Enter to return to help menu...{Colors.END}")
        self.show_help()  # Return to help menu
    
    def show_quick_start(self):
        """Show quick start guide"""
        print(f"\n{Colors.BOLD}QUICK START GUIDE{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.GREEN}Creating Archives:{Colors.END}")
        print("1. Choose 'Create Archive' from main menu")
        print("2. Drag files/folders from Finder into Terminal")
        print("3. Choose compression level (or use your saved preference)")
        print("4. Set password if needed")
        print("5. 7-Zip shows real-time progress during creation")
        
        print(f"\n{Colors.GREEN}Extracting Archives:{Colors.END}")
        print("1. Choose 'Extract Archive' from main menu")
        print("2. Drag archive file from Finder into Terminal")
        print("3. Choose all files or selective extraction")
        print("4. If selective: view contents and specify files")
        print("5. 7-Zip handles passwords and shows progress")
        
        print(f"\n{Colors.CYAN}Pro Tips:{Colors.END}")
        print("• 7-Zip shows native progress - no timeouts or hanging")
        print("• Use drag & drop - it's faster and prevents typos")
        print("• Password prompts come from 7-Zip when needed")
    
    def show_compression_help(self):
        """Show compression and formats help"""
        print(f"\n{Colors.BOLD}ARCHIVE FORMATS & COMPRESSION{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.GREEN}Supported Formats:{Colors.END}")
        print("• 7z - Best compression, password protection")
        print("• ZIP - Universal compatibility")
        print("• RAR - Extract only")
        print("• TAR, GZ, BZ2, XZ - Unix/Linux formats")
        
        print(f"\n{Colors.GREEN}Compression Presets:{Colors.END}")
        print("• Fast - Quick compression, larger files")
        print("• Balanced - Good compression, reasonable speed")
        print("• Maximum - Best compression, slower")
        print("• Custom - Choose specific level (0-9)")
        
        print(f"\n{Colors.YELLOW}Performance Notes:{Colors.END}")
        print("• Level 5 (Balanced) recommended for most users")
        print("• Level 9 uses significant memory and time")
        print("• Large archives automatically offer splitting")
    
    def show_input_help(self):
        """Show file input methods help"""
        print(f"\n{Colors.BOLD}FILE INPUT METHODS{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.GREEN}Drag & Drop (Recommended):{Colors.END}")
        print("• Drag files/folders from Finder into Terminal")
        print("• Can select multiple files at once")
        print("• Automatically handles spaces and special characters")
        print("• Prevents typos in complex paths")
        
        print(f"\n{Colors.GREEN}Manual Entry:{Colors.END}")
        print("• Type full paths when prompted")
        print("• Use quotes for paths with spaces")
        print("• Example: /Users/yourusername/Documents/file.txt")
        
        print(f"\n{Colors.CYAN}Multiple Files:{Colors.END}")
        print("• Space-separated: file1.txt file2.txt")
        print("• Quoted paths: \"file with spaces.txt\" file2.txt")
        print("• Can add more files when prompted")
    
    def show_preferences_help(self):
        """Show user preferences help"""
        print(f"\n{Colors.BOLD}USER PREFERENCES & SETTINGS{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.GREEN}Available Preferences:{Colors.END}")
        print("• Compression - Set default compression level")
        print("• Directories - Default output locations")
        print("• Auto-open - Open folders after extraction")
        print("• File Exclusions - Skip .DS_Store, temp files")
        print("• Individual clearing - Reset specific settings")
        
        print(f"\n{Colors.CYAN}Smart Features:{Colors.END}")
        print("• Smart archive naming based on content")
        print("• Remembers last used directories")
        print("• Disk space warnings before large operations")
        print("• Resume interrupted extractions")
        
        print(f"\n{Colors.YELLOW}Access:{Colors.END}")
        print("• Choose 'User Preferences' from main menu")
        print("• Settings persist between app launches")
    
    def show_advanced_help(self):
        """Show advanced features help"""
        print(f"\n{Colors.BOLD}ADVANCED FEATURES{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.GREEN}Archive Operations:{Colors.END}")
        print("• View contents - List files without extracting")
        print("• Test integrity - Verify archive health")
        print("• Selective extraction - Choose specific files")
        print("• Archive information - Technical details")
        
        print(f"\n{Colors.GREEN}Pure Passthrough Features:{Colors.END}")
        print("• Native 7-Zip progress display and speed")
        print("• Natural password prompts when needed")
        print("• No timeouts - operations run until complete")
        print("• Real-time compression/extraction feedback")
        
        print(f"\n{Colors.CYAN}Smart UX Enhancements:{Colors.END}")
        print("• Drag & drop support from Finder")
        print("• Smart archive naming based on content")
        print("• Auto-open folders after extraction")
    
    def show_troubleshooting(self):
        """Show troubleshooting help"""
        print(f"\n{Colors.BOLD}TROUBLESHOOTING{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        print(f"\n{Colors.RED}Common Issues:{Colors.END}")
        print("• File not found - Try drag & drop instead of typing")
        print("• Permission denied - Check file/folder permissions")
        print("• Archive corrupted - Use 'Test integrity' option")
        print("• Slow extraction - Extract to internal drive first")
        
        print(f"\n{Colors.YELLOW}Performance Tips:{Colors.END}")
        print("• Close other apps during large operations")
        print("• Use internal drive for temporary operations")
        print("• Check available disk space first")
        
        print(f"\n{Colors.GREEN}Getting Help:{Colors.END}")
        print("• All operations show progress indicators")
        print("• Cancel with Ctrl+C if needed")
        print("• Check User Preferences for settings")
    
    def show_all_help(self):
        """Show condensed version of all help"""
        print(f"\n{Colors.BOLD}COMPLETE HELP REFERENCE{Colors.END}")
        print(f"{Colors.BLUE}{'─'*40}{Colors.END}")
        
        # Show condensed versions of each section
        print(f"\n{Colors.BOLD}1. QUICK START:{Colors.END} Create/Extract → Drag files → Choose settings")
        print(f"{Colors.BOLD}2. FORMATS:{Colors.END} 7z (best), ZIP (compatible), RAR (extract only)")
        print(f"{Colors.BOLD}3. INPUT:{Colors.END} Drag & drop (recommended) or manual paths")
        print(f"{Colors.BOLD}4. PREFERENCES:{Colors.END} Set compression, directories, auto-open")
        print(f"{Colors.BOLD}5. ADVANCED:{Colors.END} View contents, test integrity, smart features")
        print(f"{Colors.BOLD}6. TROUBLESHOOTING:{Colors.END} Use drag & drop, check permissions")
        
        print(f"\n{Colors.CYAN}TIP: Use the numbered help menu for detailed information on each topic.{Colors.END}")

    def user_preferences_menu(self):
        """User preferences management menu"""
        while True:
            print(f"\n{Colors.PURPLE}{'─'*60}{Colors.END}")
            print(f"{Colors.BOLD}USER PREFERENCES{Colors.END}")
            print(f"{Colors.PURPLE}{'─'*60}{Colors.END}")
            
            # Show current settings
            print(f"\n{Colors.BOLD}Current Settings:{Colors.END}")
            compression_name = {
                "fast": "Fast (Level 1)",
                "balanced": "Balanced (Level 5)", 
                "maximum": "Maximum (Level 9)",
                "custom": f"Custom (Level {self.preferences['custom_compression_level']})"
            }.get(self.preferences["compression_preset"], "Balanced (Level 5)")
            
            print(f"• Compression: {compression_name}")
            print(f"• Default output: {self.preferences['default_output_directory']}")
            print(f"• Auto-open after extract: {'Yes' if self.preferences['auto_open_after_extract'] else 'No'}")
            print(f"• Remember last directory: {'Yes' if self.preferences['remember_last_directory'] else 'No'}")
            
            print(f"\n{Colors.BOLD}Options:{Colors.END}")
            print("1. Compression Preference")
            print("2. Default Directories")
            print("3. Auto-open Settings")
            print("4. File Exclusions")
            print("5. Clear Specific Setting")
            print("6. Reset All to Defaults")
            print("7. Back to Main Menu")
            
            print(f"\n{Colors.BLUE}{'─'*60}{Colors.END}")
            
            try:
                choice = input(f"{Colors.DEFAULT}Choose option (1-7): {Colors.END}").strip()
                
                if choice == "1":
                    self.compression_preferences()
                elif choice == "2":
                    self.directory_preferences()
                elif choice == "3":
                    self.auto_open_preferences()
                elif choice == "4":
                    self.exclusion_preferences()
                elif choice == "5":
                    self.clear_specific_setting()
                elif choice == "6":
                    self.reset_preferences()
                elif choice == "7":
                    break
                else:
                    self.print_warning("Invalid choice. Please enter 1-7.")
                    
            except KeyboardInterrupt:
                print(f"\n{Colors.YELLOW}Returning to main menu{Colors.END}")
                break

    def compression_preferences(self):
        """Set compression preferences"""
        print(f"\n{Colors.BOLD}COMPRESSION PREFERENCE{Colors.END}")
        current = self.preferences['compression_preset']
        if current == "custom":
            current_text = f"Custom (Level {self.preferences['custom_compression_level']})"
        else:
            current_text = current.title()
        print(f"Current: {current_text}")
        print()
        print("1. Fast (Level 1) - Always use fast compression")
        print("2. Balanced (Level 5) - Always use balanced compression")  
        print("3. Maximum (Level 9) - Always use maximum compression")
        print("4. Always Ask - Show preset menu each time")
        print("5. Custom Level - Set specific number (0-9)")
        print("6. Clear Setting - Reset to 'Always Ask'")
        print("7. Back to Preferences")
        
        choice = input(f"\n{Colors.DEFAULT}Choose (1-7): {Colors.END}").strip()
        
        if choice == "1":
            self.preferences["compression_preset"] = "fast"
        elif choice == "2":
            self.preferences["compression_preset"] = "balanced"
        elif choice == "3":
            self.preferences["compression_preset"] = "maximum"
        elif choice == "4":
            self.preferences["compression_preset"] = "ask"
        elif choice == "5":
            level = input(f"{Colors.DEFAULT}Enter compression level (0-9): {Colors.END}").strip()
            try:
                level_int = int(level)
                if 0 <= level_int <= 9:
                    self.preferences["compression_preset"] = "custom"
                    self.preferences["custom_compression_level"] = level_int
                else:
                    self.print_warning("Please enter a number between 0 and 9")
                    return
            except ValueError:
                self.print_warning("Please enter a valid number")
                return
        elif choice == "6":
            self.preferences["compression_preset"] = "ask"  # Reset to always ask
            self.print_success("Compression preference cleared - will ask each time")
        elif choice == "7":
            return
        else:
            self.print_warning("Invalid choice")
            return
        
        if choice != "6":  # Don't show "saved" message for clear
            self.save_preferences()
            self.print_success("Compression preference saved!")
        else:
            self.save_preferences()

    def directory_preferences(self):
        """Set directory preferences"""
        print(f"\n{Colors.BOLD}DIRECTORY PREFERENCES{Colors.END}")
        print(f"Current default: {self.preferences['default_output_directory']}")
        remember_status = "enabled" if self.preferences['remember_last_directory'] else "disabled"
        print(f"Remember last directory: {remember_status}")
        print()
        print("1. Set new default output directory")
        print("2. Toggle 'Remember last directory'")
        print("3. Clear default directory - Reset to ~/Desktop")
        print("4. Clear last directory memory")
        print("5. Back to Preferences")
        
        choice = input(f"\n{Colors.DEFAULT}Choose (1-5): {Colors.END}").strip()
        
        if choice == "1":
            new_dir = input(f"{Colors.DEFAULT}Enter default directory path: {Colors.END}").strip()
            if new_dir and os.path.isdir(os.path.expanduser(new_dir)):
                self.preferences["default_output_directory"] = os.path.expanduser(new_dir)
                self.save_preferences()
                self.print_success("Default directory updated!")
            else:
                self.print_warning("Invalid directory path")
        elif choice == "2":
            self.preferences["remember_last_directory"] = not self.preferences["remember_last_directory"]
            self.save_preferences()
            status = "enabled" if self.preferences["remember_last_directory"] else "disabled"
            self.print_success(f"Remember last directory {status}!")
        elif choice == "3":
            self.preferences["default_output_directory"] = os.path.expanduser("~/Desktop")
            self.save_preferences()
            self.print_success("Default directory reset to ~/Desktop!")
        elif choice == "4":
            if "last_output_directory" in self.preferences:
                del self.preferences["last_output_directory"]
                self.save_preferences()
                self.print_success("Last directory memory cleared!")
            else:
                self.print_info("No last directory to clear")
        elif choice == "5":
            return
        else:
            self.print_warning("Invalid choice")

    def auto_open_preferences(self):
        """Set auto-open preferences"""
        current = "enabled" if self.preferences["auto_open_after_extract"] else "disabled"
        print(f"\n{Colors.BOLD}AUTO-OPEN SETTINGS{Colors.END}")
        print(f"Auto-open folder after extraction: {current}")
        print()
        print("1. Enable auto-open")
        print("2. Disable auto-open")
        print("3. Back to Preferences")
        
        choice = input(f"\n{Colors.DEFAULT}Choose (1-3): {Colors.END}").strip()
        
        if choice == "1":
            self.preferences["auto_open_after_extract"] = True
            self.save_preferences()
            self.print_success("Auto-open enabled!")
        elif choice == "2":
            self.preferences["auto_open_after_extract"] = False
            self.save_preferences()
            self.print_success("Auto-open disabled!")
        elif choice == "3":
            return
        else:
            self.print_warning("Invalid choice")

    def exclusion_preferences(self):
        """Set file exclusion preferences"""
        print(f"\n{Colors.BOLD}FILE EXCLUSIONS{Colors.END}")
        print("Current exclusions:")
        for pattern in self.preferences["exclude_patterns"]:
            print(f"• {pattern}")
        print()
        print("1. Add exclusion pattern")
        print("2. Remove exclusion pattern") 
        print("3. Reset to defaults")
        print("4. Back to Preferences")
        
        choice = input(f"\n{Colors.DEFAULT}Choose (1-4): {Colors.END}").strip()
        
        if choice == "1":
            pattern = input(f"{Colors.DEFAULT}Enter pattern to exclude (e.g., *.tmp): {Colors.END}").strip()
            if pattern and pattern not in self.preferences["exclude_patterns"]:
                self.preferences["exclude_patterns"].append(pattern)
                self.save_preferences()
                self.print_success(f"Added exclusion: {pattern}")
            else:
                self.print_warning("Invalid or duplicate pattern")
        elif choice == "2":
            if self.preferences["exclude_patterns"]:
                print("Current patterns:")
                for i, pattern in enumerate(self.preferences["exclude_patterns"], 1):
                    print(f"{i}. {pattern}")
                try:
                    idx = int(input(f"{Colors.DEFAULT}Remove which pattern (number): {Colors.END}").strip()) - 1
                    if 0 <= idx < len(self.preferences["exclude_patterns"]):
                        removed = self.preferences["exclude_patterns"].pop(idx)
                        self.save_preferences()
                        self.print_success(f"Removed exclusion: {removed}")
                    else:
                        self.print_warning("Invalid number")
                except ValueError:
                    self.print_warning("Please enter a valid number")
            else:
                self.print_info("No exclusion patterns to remove")
        elif choice == "3":
            self.preferences["exclude_patterns"] = [".DS_Store", ".Thumbs.db", "Thumbs.db"]
            self.save_preferences()
            self.print_success("Exclusions reset to defaults!")
        elif choice == "4":
            return
        else:
            self.print_warning("Invalid choice")

    def clear_specific_setting(self):
        """Clear individual preference settings"""
        print(f"\n{Colors.BOLD}CLEAR SPECIFIC SETTING{Colors.END}")
        print("Choose which setting to clear:")
        print()
        print("1. Compression preference - Reset to 'Always Ask'")
        print("2. Default output directory - Reset to ~/Desktop")
        print("3. Last directory memory - Clear remembered path")
        print("4. Auto-open setting - Reset to disabled")
        print("5. All file exclusions - Reset to defaults")
        print("6. Back to Preferences")
        
        choice = input(f"\n{Colors.DEFAULT}Choose (1-6): {Colors.END}").strip()
        
        if choice == "1":
            self.preferences["compression_preset"] = "ask"
            self.save_preferences()
            self.print_success("Compression preference cleared - will ask each time")
        elif choice == "2":
            self.preferences["default_output_directory"] = os.path.expanduser("~/Desktop")
            self.save_preferences()
            self.print_success("Default directory reset to ~/Desktop")
        elif choice == "3":
            if "last_output_directory" in self.preferences:
                del self.preferences["last_output_directory"]
                self.save_preferences()
                self.print_success("Last directory memory cleared")
            else:
                self.print_info("No last directory to clear")
        elif choice == "4":
            self.preferences["auto_open_after_extract"] = False
            self.save_preferences()
            self.print_success("Auto-open setting reset to disabled")
        elif choice == "5":
            self.preferences["exclude_patterns"] = [".DS_Store", ".Thumbs.db", "Thumbs.db"]
            self.save_preferences()
            self.print_success("File exclusions reset to defaults")
        elif choice == "6":
            return
        else:
            self.print_warning("Invalid choice")

    def main_menu(self):
        while True:
            self.print_header()
            
            print(f"{Colors.BOLD}Main Menu:{Colors.END}")
            print("1. Create Archive")
            print("2. Extract Archive")
            print("3. View Archive Contents")
            print("4. User Preferences")
            print("5. Help & Tips")
            print("6. Exit")
            
            print(f"\n{Colors.BLUE}{'─'*60}{Colors.END}")
            
            try:
                choice = input(f"{Colors.DEFAULT}Choose option (1-6): {Colors.END}").strip()
                
                if choice == "1":
                    self.create_archive()
                elif choice == "2":
                    self.extract_archive()
                elif choice == "3":
                    self.view_archive()
                elif choice == "4":
                    self.user_preferences_menu()
                elif choice == "5":
                    self.show_help()
                elif choice == "6":
                    print(f"{Colors.GREEN}Thank you for using 7-Zip CLI!{Colors.END}")
                    break
                else:
                    self.print_warning("Invalid choice. Please enter 1-6.")
                
                if choice in ["1", "2", "3"]:
                    input("Press Enter to continue...")
                    
            except KeyboardInterrupt:
                print(f"\n\n{Colors.GREEN}Goodbye!{Colors.END}")
                break
    
    def run(self):
        if not self.check_7zip():
            sys.exit(1)
        
        self.main_menu()

def main():
    """Entry point for command line usage"""
    parser = argparse.ArgumentParser(
        description="CLI Interface for 7-Zip on macOS",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 7zip_cli.py                    # Start interactive CLI
  python3 7zip_cli.py --help             # Show this help

Features:
  • Create password-protected archives
  • Extract any supported archive format  
  • View archive contents without extraction
  • Support for folders and entire drives
  • Drag & drop support from Finder
  • Support for 7z, zip, rar, tar, gz, and more

Tips:
  • Use drag & drop from Finder for easy file paths
  • Archives are saved to Desktop by default
  • Level 5 compression recommended for most use cases
  • Password protection uses AES-256 encryption
        """)
    
    parser.add_argument('--version', action='version', version='7-Zip CLI v1.0')
    
    args = parser.parse_args()
    
    # Create and run the CLI
    app = SevenZipCLI()
    app.run()

if __name__ == "__main__":
    main()
