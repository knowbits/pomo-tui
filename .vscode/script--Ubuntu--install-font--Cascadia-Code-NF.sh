#!/bin/bash

# Ensure GitHub CLI is installed
if ! command -v gh &> /dev/null; then
  echo "GitHub CLI (gh) not found. Please install it first."
  exit 1
fi

# Get latest release of Cascadia Code from Microsoft repo
echo "Fetching latest Cascadia Code release info..."
REPO="microsoft/cascadia-code"
ASSET_NAME="CascadiaCode-NF.ttf"

# Fetch the release download URL for the Nerd Font TTF ZIP
DOWNLOAD_URL=$(gh release view -R $REPO --json assets -q ".assets[] | select(.name | test(\"CascadiaCode.*[.]zip\")) | .url")

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Could not find CascadiaCode Nerd Font zip in latest release."
  exit 1
fi

# Create fonts directory
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"

# Download and unzip font
echo "Downloading font zip..."
TEMP_ZIP="/tmp/CascadiaCodeNF.zip"
gh release download -R $REPO --pattern "CascadiaCode*.zip" -D /tmp/

echo "Installing fonts..."
unzip -o "$TEMP_ZIP" -d "$FONT_DIR"

# Refresh font cache
echo "Updating font cache..."
fc-cache -fv

echo "✅ Cascadia Code NF installed successfully!"

echo ""
echo "Here are the installed font files:"

fc-list | grep -i "Cascadia Code NF"
