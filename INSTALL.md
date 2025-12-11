# Installation

## Requirements

- **CLI:** macOS 10.14+, Python 3.7+ (included with macOS)
- **GUI:** macOS 12.0+

## Install

### Download Pre-built Apps (Recommended)

1. Go to the [Releases](https://github.com/hamiltonbarber/cli-gui-7zip-macos/releases) page
2. Download the latest `7-Zip.CLI.app.zip` or `7-Zip.GUI.app.zip`
3. Unzip and move to Applications folder
4. Double-click to launch

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

## First Launch

macOS may show security warning on first launch:
1. Right-click app → "Open"
2. Click "Open" in dialog

Or go to System Preferences → Security & Privacy → Click "Open Anyway"

## Troubleshooting

**App won't open:** Try right-click → Open method above

**CLI won't run:** Check `python3 --version` shows 3.7+

**GUI won't build:** Install Xcode Command Line Tools: `xcode-select --install`

**7-Zip errors:** App includes 7-Zip executable, no separate installation needed

## Uninstall

Drag app to Trash. Remove preferences: `rm -rf ~/Library/Containers/com.7zipgui.macos`
