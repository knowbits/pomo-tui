#!/bin/bash
# start-local-vscode.sh
#
# This script starts VS Code (or Code-Insiders) using only
# the extensions installed in a local folder (e.g. .vscode-extensions).
#
# It uses the --extensions-dir flag to specify the exact location
# of the extensions and ensures that globally installed extensions
# (in the default user folder) are not loaded.
#
# Usage: ./start-local-vscode.sh [optional arguments to VS Code]
#

set -euo pipefail

# Capture all parameters / options to the script
SCRIPT_PARAMETERS="$@"

# Get the full path of this script's folder
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Set the local extensions directory (using an absolute path)
LOCAL_EXTENSIONS_DIR="${SCRIPT_DIR}/extensions"

# Set the local "User Data Directory" (using an absolute path)
LOCAL_USER_DATA_DIR="${SCRIPT_DIR}/../.vscode-data-dir"

# Set the project's root folder (using an absolute path)
PROJECT_ROOT="${SCRIPT_DIR}/../"

# Verify the local extensions directory exists.
if [ ! -d "$LOCAL_EXTENSIONS_DIR" ]; then
  echo "Local extensions directory '$LOCAL_EXTENSIONS_DIR' does not exist. Exiting."
  exit 1
fi

# Define the VS Code CLI command (change to 'code' if needed instead of 'code-insiders')
VSCODE_COMMAND=code-insiders

# NOTE: Need to use an array so that the launch options will be expanded correctly
VSCODE_OPTIONS=()

# Disable sandboxing for CLI: A common workaround for running Electron applications on Linux.
VSCODE_OPTIONS+=("--no-sandbox")

# Specify a local "user data dir" directory, to avoid all global and user settings and extensions.
VSCODE_OPTIONS+=("--user-data-dir" "$LOCAL_USER_DATA_DIR")

# Specify the local extensions directory
VSCODE_OPTIONS+=("--extensions-dir" "$LOCAL_EXTENSIONS_DIR")

# Disable GPU acceleration: This can help avoid issues with some graphics drivers.
# VSCODE_OPTIONS+=("--disable-gpu")

# Disable telemetry: This prevents VS Code from sending usage data.
# VSCODE_OPTIONS+=("--disable-telemetry")

# Disable crash reporting: This prevents VS Code from sending crash reports.
# VSCODE_OPTIONS+=("--disable-crash-reporter")

# Disable updates: This prevents VS Code from checking for updates.
# VSCODE_OPTIONS+=("--disable-updates")

# Disable extension auto-update: This prevents extensions from updating automatically.
# VSCODE_OPTIONS+=("--disable-extension-auto-update")

# Disable extension recommendations: This prevents VS Code from suggesting extensions.
# VSCODE_OPTIONS+=("--disable-extension-recommendations")

# Disable extension telemetry: This prevents extensions from sending telemetry data.
# VSCODE_OPTIONS+=("--disable-extension-telemetry")

# Disable extension crash reporting: This prevents extensions from sending crash reports.
# VSCODE_OPTIONS+=("--disable-extension-crash-reporter")

# Disable extension auto-installation: This prevents VS Code from automatically installing extensions.
# VSCODE_OPTIONS+=("--disable-extension-auto-installation")

# Disable extension auto-activation: This prevents extensions from activating automatically.
# VSCODE_OPTIONS+=("--disable-extension-auto-activation")

# Disable extension auto-update notifications: This prevents VS Code from notifying about extension updates.
# VSCODE_OPTIONS+=("--disable-extension-auto-update-notifications")

# Disable extension auto-reload: This prevents VS Code from automatically reloading extensions.
# VSCODE_OPTIONS+=("--disable-extension-auto-reload")

# Disable extension auto-restart: This prevents VS Code from automatically restarting extensions.
# VSCODE_OPTIONS+=("--disable-extension-auto-restart")

# Disable extension auto-installation notifications: This prevents VS Code from notifying about extension installations.
# VSCODE_OPTIONS+=("--disable-extension-auto-installation-notifications")

echo "Starting VS Code with local extensions directory: $LOCAL_EXTENSIONS_DIR"

# Launch VS Code with the specified extensions directory.
# All additional command-line arguments are passed on to VS Code.
#
# With "exec": The benefits of using "exec" to start code-insiders:
#  - It replaces the current shell process with the VS Code Insiders process.
#  - No extra shell process remains running after VS Code starts.
#  - When you close VS Code, the terminal session ends (if the script was run as the main shell process).
#  - It can slightly reduce resource usage since there’s no parent shell left waiting.
#
# Without "exec":
#  - The shell that launched the script will stay alive until VS Code exits.
#  - You may see an extra process in ps or top.
#  - In the terminal, you’ll get your prompt back only after VS Code exits.
#
# Using "exec" is considered a best practice for "launcher scripts" like this.

exec "$VSCODE_COMMAND" "${VSCODE_OPTIONS[@]}" "$PROJECT_ROOT" "$SCRIPT_PARAMETERS"
