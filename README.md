# Command Line and GUI Interface for 7-Zip on macOS

Simple interface for 7-Zip archive operations on macOS.

> **Note:** This is an independent project and is not affiliated with or endorsed by Igor Pavlov or the official 7-Zip project.

![License](https://img.shields.io/badge/license-LGPL--3.0-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2012.0+-lightgrey.svg)

## What This Is

Two ways to use 7-Zip on macOS:

**CLI Application:** Interactive command-line interface with full 7-Zip features
**GUI Application:** Basic graphical interface for common operations

## Supported Formats

| Format | Create | Extract | View |
|--------|--------|---------|------|
| 7z | Yes | Yes | Yes |
| ZIP | Yes | Yes | Yes |
| RAR | No | Yes | Yes |
| TAR | Yes | Yes | Yes |
| GZ/BZ2/XZ | Yes | Yes | Yes |

## Installation

### Download Pre-built Apps (Recommended)

Download the latest release from the [Releases](https://github.com/hamiltonbarber/cli-gui-7zip-macos/releases) page:

1. Download `7-Zip.CLI.app.zip` or `7-Zip.GUI.app.zip`
2. Unzip and move to Applications folder
3. Double-click to launch

### Build from Source

**CLI Application (Python):**
```bash
git clone https://github.com/hamiltonbarber/cli-gui-7zip-macos.git
cd cli-gui-7zip-macos
python3 7zip_cli.py
```

**GUI Application (Xcode):**
```bash
git clone https://github.com/hamiltonbarber/cli-gui-7zip-macos.git
cd cli-gui-7zip-macos/7ZipGUI
xcodebuild -project 7ZipGUI.xcodeproj -scheme 7ZipGUI build
```

See [INSTALL.md](INSTALL.md) for details.

## Usage

### CLI Application
- Double-click `7-Zip CLI.app` to launch
- Interactive menus guide you through operations
- Drag file paths from Finder when prompted
- Supports password protection, compression levels, archive splitting

### GUI Application
- **Create:** Drag files to interface, set options, create archive
- **Extract:** Load archive, select files to extract, choose destination
- **View:** Browse archive contents without extracting

## Requirements

- **CLI:** macOS 10.14+, Python 3.7+ (included with macOS)
- **GUI:** macOS 12.0+

## License

LGPL-3.0 License. Includes 7-Zip (by Igor Pavlov) under LGPL 2.1+.

See [LICENSE](LICENSE) and [THIRD-PARTY-LICENSES.txt](THIRD-PARTY-LICENSES.txt) for details.

## Author

Hamilton Barber - [hamiltonbarber.com](https://www.hamiltonbarber.com)

Support if you want, but don't feel like you need to: [PayPal](https://paypal.me/HamiltonBBarber)
