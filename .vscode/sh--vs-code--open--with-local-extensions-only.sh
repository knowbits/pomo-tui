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

# Define the VS Code CLI command (change to 'code' if needed instead of 'code-insiders')
VSCODE_COMMAND=code-insiders

# Get the full path of this script's folder
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Set the local extensions directory (using an absolute path)
LOCAL_EXTENSIONS_DIR="${SCRIPT_DIR}/../.vscode-extensions"

# Verify the local extensions directory exists.
if [ ! -d "$LOCAL_EXTENSIONS_DIR" ]; then
    echo "Local extensions directory '$LOCAL_EXTENSIONS_DIR' does not exist. Exiting."
    exit 1
fi

echo "Starting VS Code with local extensions directory: $LOCAL_EXTENSIONS_DIR"

# Launch VS Code with the specified extensions directory.
# All additional command-line arguments are passed on to VS Code.
exec "$VSCODE_COMMAND" --extensions-dir "$LOCAL_EXTENSIONS_DIR" "$@"
