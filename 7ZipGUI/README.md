# CLI Interface for 7-Zip - Swift GUI

This directory contains the SwiftUI-based GUI application for the CLI Interface for 7-Zip.

## Files

- **App.swift** - Main app entry point and window configuration
- **ContentView.swift** - Main UI with tabbed interface (Create/Extract/View)
- **ArchiveViewModel.swift** - Business logic and Python CLI integration

## Architecture

The GUI app calls the existing Python CLI script as a subprocess, parsing its output for progress updates and results. This allows reusing all the existing archive logic while providing a native macOS interface.

## Features

### Create Archive Tab
- Drag & drop file selection from Finder
- File browser integration
- Compression level slider (0-9)
- Password protection options
- Archive format selection (7z, ZIP, TAR)
- Real-time progress display

### Extract Archive Tab
- Archive file picker
- Destination folder selection
- All files or selective extraction
- Archive preview before extraction

### View Archive Tab
- Archive content listing
- File details and structure display

## Setup

1. Open Xcode
2. Create new macOS app project
3. Replace default files with these Swift files
4. Add the Python CLI script to the app bundle
5. Build and run

## Integration with Python CLI

The ViewModel executes the Python script with command-line arguments:
```bash
python3 7zip_cli.py --create --files file1.txt file2.txt --output archive.7z
```

Progress is parsed from 7-Zip's stdout output, providing real-time updates to the GUI.
