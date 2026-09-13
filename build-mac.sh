#!/bin/bash
# Build script for macOS

set -e

echo "Building hanshuang-codex for macOS..."

# Activate virtual environment if it exists
if [[ -d ".venv" ]]; then
    echo "Activating virtual environment..."
    source .venv/bin/activate
fi

# Check if PyInstaller is installed
if ! command -v pyinstaller &> /dev/null; then
    echo "PyInstaller not found. Installing..."
    pip install pyinstaller
fi

# Clean previous build
rm -rf build dist

# Build with PyInstaller (without icon for now)
pyinstaller --name="寒霜破甲工具" \
    --windowed \
    --onedir \
    --add-data="install-codex.sh:." \
    --add-data="install-claude.sh:." \
    --add-data="寒霜v1.2.md:." \
    --add-data="寒霜v3.md:." \
    --add-data="寒霜v4.md:." \
    --add-data="寒霜v4-claude.md:." \
    --add-data="寒霜-变体B-v3-英文.md:." \
    --add-data="寒霜-flash-v2.md:." \
    --add-data="寒霜-zcode版.md:." \
    --add-data="zcode-prompt.md:." \
    --hidden-import=PySide6 \
    --hidden-import=PySide6.QtCore \
    --hidden-import=PySide6.QtGui \
    --hidden-import=PySide6.QtWidgets \
    --osx-bundle-identifier=com.hanshuang.codex \
    fj_tool.py

echo "Build complete! Application bundle is in dist/寒霜破甲工具.app"
