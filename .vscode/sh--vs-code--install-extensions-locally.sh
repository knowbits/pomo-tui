#!/bin/bash
# install-extensions.sh
#
# This script force‐installs every VS Code extension listed in
# .vscode/mandatory-extensions.txt into a local folder (.vscode-extensions).
#
# Each non‑comment, non‑empty line in .vscode/mandatory-extensions.txt should be in one of:
#
#    ExtensionID
# or:
#    ExtensionID, USE-PRE-RELEASE
#
# For lines ending with ", USE-PRE-RELEASE", the script passes --pre-release
# to the VS Code CLI so that the pre‑release version is installed.
#
# After installation, the script scans the installed extensions for those
# pulled in indirectly (via dependency or extension pack) and prints a summary
# which includes for each extra extension its status ("dependency" or "in pack")
# and the parent extension(s) that caused its installation.
#
# All error output is printed. If an error occurs (especially one with the text
# "v8::ToLocalChecked Empty MaybeLocal") a helpful hint is provided, and the
# script aborts immediately.
#
set -euo pipefail

# ANSI color definitions.
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
NC="\033[0m"  # No Color

# Store deleted extensions
declare -a deleted_extensions=()

# Use VS Code Insiders CLI (change to "code" if needed)
VSCODE=code-insiders

# Get the full path of this script's folder
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Set the local extensions directory (absolute path)
EXT_DIR="${SCRIPT_DIR}/../.vscode-extensions"

# Get list of currently installed extensions before any changes
declare -a initial_extensions=()
if [ -d "$EXT_DIR" ]; then
  while IFS= read -r line; do
    initial_extensions+=( "$line" )
  done < <("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR")
fi
# Set the path to the mandatory extensions file
EXT_FILE="${SCRIPT_DIR}/mandatory-extensions.txt"

# Function to trim whitespace from a string.
trim() {
  echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Error trap: print the line number and abort.
handle_error() {
    echo -e "${RED}Error at line $1. Aborting.${NC}"
    exit 1
}
trap 'handle_error $LINENO' ERR

echo -e "${BLUE}=== VS Code Extensions Installer ===${NC}\n"

# Verify that the VS Code CLI exists.
command -v "$VSCODE" >/dev/null 2>&1 || { echo -e "${RED}Error: VS Code CLI ('$VSCODE') not found.${NC}"; exit 1; }

# Create the local extensions directory if it doesn't exist.
mkdir -p "$EXT_DIR" || { echo -e "${RED}Error: Could not create directory ${EXT_DIR}.${NC}"; exit 1; }
echo -e "${BLUE}Using local extensions directory: ${EXT_DIR}${NC}"

# Ensure that the mandatory file exists.
if [ ! -f "$EXT_FILE" ]; then
  echo -e "${RED}Error: ${EXT_FILE} not found! Please create this file with the extension IDs.${NC}"
  exit 1
fi

# Read lines from the mandatory extensions file; ignore blank lines and lines starting with "//".
declare -a EXT_LINES=()
while IFS= read -r line; do
  trimmed=$(trim "$line")
  if [[ -z "$trimmed" || "$trimmed" == "//"* ]]; then
    continue
  fi
  EXT_LINES+=( "$trimmed" )
done < "$EXT_FILE"

if [[ ${#EXT_LINES[@]} -eq 0 ]]; then
  echo -e "${RED}Error: No valid extensions found in ${EXT_FILE}.${NC}"
  exit 1
fi

# Build a set of mandatory extension IDs (normalized to lowercase) for later extra-checking.
declare -A mandatorySet
for entry in "${EXT_LINES[@]}"; do
  if [[ "$entry" == *","* ]]; then
    IFS=',' read -r raw_ext _ <<< "$entry"
    ext_id=$(trim "$raw_ext")
  else
    ext_id=$(trim "$entry")
  fi
  key=$(echo "$ext_id" | tr '[:upper:]' '[:lower:]')
  mandatorySet["$key"]=1
done

echo -e "${BLUE}Force-installing mandatory extensions from ${EXT_FILE}...${NC}"

results=()  # Array to store installation summary.

# install_extension: Installs one extension.
# Arguments:
#   $1: Extension ID
#   $2: Extra flag (e.g. "--pre-release") or empty.
install_extension() {
  local ext_id="$1"
  local extra_flag="$2"
  local norm_id
  norm_id=$(echo "$ext_id" | tr '[:upper:]' '[:lower:]')

  # Get version before installation (if extension exists)
  local previous_version
  previous_version=$("$VSCODE" --list-extensions --show-versions --extensions-dir "$EXT_DIR" \
    | grep -i "^$(echo "$ext_id" | tr '[:upper:]' '[:lower:]')@" | cut -d'@' -f2 || echo "")

  if [ -n "$extra_flag" ]; then
    echo -e "${BLUE}Installing ${ext_id} with pre-release...${NC}"
  else
    echo -e "${BLUE}Installing ${ext_id}...${NC}"
  fi

  # Capture all output from the installation command.
  local output
  output=$("$VSCODE" --extensions-dir "$EXT_DIR" --install-extension "$ext_id" --force $extra_flag 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    echo -e "${RED}Error installing ${ext_id}.${NC}"
    echo "$output"
    if echo "$output" | grep -q "v8::ToLocalChecked Empty MaybeLocal"; then
      echo -e "${RED}Hint: VS Code encountered a V8 error while processing $ext_id. This may indicate a bug in the extension or in VS Code. Try updating VS Code or check for known issues for this extension.${NC}"
    fi
    exit 1
  else
    echo "$output"
  fi

  # Retrieve the installed version.
  local installed_version
  installed_version=$("$VSCODE" --list-extensions --show-versions --extensions-dir "$EXT_DIR" \
    | grep -i "^$(echo "$ext_id" | tr '[:upper:]' '[:lower:]')@" | cut -d'@' -f2 || echo "unknown")

  # Change status determination logic
  local status
  if [ -z "$previous_version" ]; then
    status="NEW"
  elif [ "$previous_version" != "$installed_version" ]; then
    status="UPDATED"
  else
    status="-"
  fi

  results+=("$ext_id|$status|$installed_version")
}

# Process each entry from the mandatory file.
for entry in "${EXT_LINES[@]}"; do
  if [[ "$entry" == *","* ]]; then
    IFS=',' read -r raw_ext raw_flag <<< "$entry"
    ext_id=$(trim "$raw_ext")
    flag=$(trim "$raw_flag")
    if [[ "$flag" == "USE-PRE-RELEASE" ]]; then
      install_extension "$ext_id" "--pre-release"
    else
      install_extension "$ext_id" ""
    fi
  else
    ext_id=$(trim "$entry")
    install_extension "$ext_id" ""
  fi
done

# ---------------------------------------------------------------
# Now, analyze local installation to list extra (indirect) extensions.
#
# For every installed extension folder in EXT_DIR that has a package.json,
# if that extension belongs to a mandatory extension (i.e. its normalized ID is
# in mandatorySet), then scan its package.json for "extensionDependencies" and "extensionPack".
# For every dependency not explicitly mandatory, record its status and parent.
#
declare -A extra_status   # keyed by extra extension ID (lowercase)
declare -A extra_parent   # keyed by extra extension ID (lowercase)

for folder in "$EXT_DIR"/*; do
  if [ -d "$folder" ] && [ -f "$folder/package.json" ]; then
    ext_manifest_id=$(jq -r '.publisher + "." + .name' "$folder/package.json" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    # Process only if folder belongs to a mandatory extension.
    if [[ -n "${mandatorySet[$ext_manifest_id]:-}" ]]; then
      parent="$ext_manifest_id"
      # Process extensionDependencies.
      deps=$(jq -rc '.extensionDependencies // []' "$folder/package.json" 2>/dev/null)
      for dep in $(echo "$deps" | jq -r '.[]'); do
        dep=$(echo "$dep" | tr '[:upper:]' '[:lower:]')
        if [[ -z "${mandatorySet[$dep]:-}" ]]; then
          if [[ -z "${extra_status[$dep]:-}" ]]; then
            extra_status["$dep"]="dependency"
            extra_parent["$dep"]="$parent"
          else
            if [[ "${extra_parent[$dep]}" != *"$parent"* ]]; then
              extra_parent["$dep"]+=", $parent"
            fi
          fi
        fi
      done
      # Process extensionPack items.
      pack=$(jq -rc '.extensionPack // []' "$folder/package.json" 2>/dev/null)
      for item in $(echo "$pack" | jq -r '.[]'); do
        item=$(echo "$item" | tr '[:upper:]' '[:lower:]')
        if [[ -z "${mandatorySet[$item]:-}" ]]; then
          if [[ -z "${extra_status[$item]:-}" ]]; then
            extra_status["$item"]="in pack"
            extra_parent["$item"]="$parent"
          else
            if [[ "${extra_parent[$item]}" != *"$parent"* ]]; then
              extra_parent["$item"]+=", $parent"
            fi
          fi
        fi
      done
    fi
  fi
done

# Get a complete list of installed extensions (normalized) from the CLI.
declare -a installedList
declare -a extraExtensions=()
while IFS= read -r line; do
   installedList+=( "$(echo "$line" | tr '[:upper:]' '[:lower:]')" )
done < <("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR")

# Identify extra extensions: those installed but not explicitly in the mandatory set or deleted
if [ ${#installedList[@]} -gt 0 ]; then
  for inst in "${installedList[@]}"; do
    # Skip if it's in mandatory set or deleted extensions
    is_deleted=false
    for del in "${deleted_extensions[@]}"; do
      if [[ "${del,,}" == "${inst,,}" ]]; then
        is_deleted=true
        break
      fi
    done

    if [[ -n "${mandatorySet[$inst]:-}" ]] || $is_deleted; then
      continue
    fi

    # Add if has a known status (dependency or in pack)
    if [[ -n "${extra_status[$inst]:-}" ]]; then
      extraExtensions+=( "$inst" )
    fi
  done
fi

# Check for extensions to delete
for ext in "${initial_extensions[@]}"; do
  ext_lower=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  if [[ -z "${mandatorySet[$ext_lower]:-}" ]]; then
    echo -e "${YELLOW}Removing deleted extension: $ext${NC}"
    "$VSCODE" --extensions-dir "$EXT_DIR" --uninstall-extension "$ext"
    deleted_extensions+=("$ext")
  fi
done

# ---------------------------------------------------------------
# Print mandatory installation summary.
echo -e "\n${GREEN}Installed extensions:${NC}"
printf "%-40s %-30s %-20s\n" "Extension ID" "Status" "Version"
printf '%.0s=' {1..100}; echo ""
for res in "${results[@]}"; do
  IFS='|' read -r id status version <<< "$res"
  printf "%-40s %-30s %-20s\n" "$id" "$status" "$version"
done

# Print deleted extensions summary if any were deleted
if [[ ${#deleted_extensions[@]} -gt 0 ]]; then
  echo -e "\n${RED}Deleted extensions:${NC}"
  printf '%.0s=' {1..100}; echo ""
  for ext in "${deleted_extensions[@]}"; do
    printf "%-40s\n" "$ext"
  done
fi

# Print extra (indirect) extensions summary.
if [[ ${#extraExtensions[@]} -gt 0 ]]; then
  echo -e "\n${YELLOW}'Indirect' extensions${NC} (dependency or part of pack):"
  printf "%-40s %-20s %-40s\n" "Extra Extension ID" "Status" "Parent Extension(s)"
  printf '%.0s=' {1..100}; echo ""
  for extra in "${extraExtensions[@]}"; do
    stat=${extra_status[$extra]:-"unknown"}
    parent=${extra_parent[$extra]:-"none"}
    printf "%-40s %-20s %-40s\n" "$extra" "$stat" "$parent"
  done
fi

# Save a pretty-printed copy of extensions.json if it exists
if [ -f "$EXT_DIR/extensions.json" ]; then
    echo -e "\n${BLUE}Saving pretty-printed copy of extensions.json...${NC}"
    if jq '.' "$EXT_DIR/extensions.json" > "$EXT_DIR/extensions-pretty-printed.json"; then
        echo -e "${GREEN}Successfully saved $EXT_DIR/extensions-pretty-printed.json${NC}"
    else
        echo -e "${RED}Failed to create pretty-printed copy of extensions.json${NC}"
    fi
fi

echo -e "\n=== Installation Complete ===\n"
