#!/bin/bash
# install-extensions.sh
#
# This script force‐installs VS Code extensions listed in extensions.txt
# into a local ./extensions folder. It intelligently manages dependencies
# and extension packs, and uninstalls any extensions that are no longer required.
#
# All installation and uninstallation is handled by the VS Code CLI to ensure
# consistency and proper dependency management.
#
# Usage:
#   1. List top-level extension IDs in 'extensions.txt'.
#   2. To install a pre-release version, add ', USE-PRE-RELEASE' after the ID.
#   3. Run the script: ./install-extensions.sh
#
set -euo pipefail

# --- Configuration ---

readonly SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
# Directory where extensions will be installed.
readonly EXT_DIR="${SCRIPT_DIR}/extensions"
readonly EXT_FILE="${SCRIPT_DIR}/extensions.txt"
readonly USER_DATA_DIR="${SCRIPT_DIR}/../.vscode-data-dir"

# Use 'code' for stable or 'code-insiders' for insiders.
readonly VSCODE=code-insiders

# NOTE: Need to use an array so that the "launch options" will be expanded correctly
VSCODE_OPTIONS=()
# Disable sandboxing for CLI: A common workaround for running Electron applications on Linux.
VSCODE_OPTIONS+=("--no-sandbox")
# Disable GPU acceleration: This can help avoid issues with some graphics drivers.
VSCODE_OPTIONS+=("--disable-gpu")
# Use local extensions directory: This allows us to install extensions locally.
VSCODE_OPTIONS+=("--extensions-dir" "$EXT_DIR")
# Use a local "user data directory":
# Prevents VS Code from loading any of the User / Global settings or extensions
VSCODE_OPTIONS+=("--user-data-dir" "$USER_DATA_DIR")

# --- ANSI Color Definitions ---
readonly RED="\033[0;31m"
readonly GREEN="\033[0;32m"
readonly YELLOW="\033[0;33m"
readonly BLUE="\033[0;34m"
readonly MAGENTA="\033[0;35m"
readonly CYAN="\033[0;36m"
readonly NC="\033[0m" # No Color

# --- Error Handling ---
# Redirect stderr to logger and console for comprehensive logging.
exec 2> >(tee -a >(logger -t "$(basename "$0")") >&2)

handle_error() {
  local exit_code=$?
  local line_no=$1
  echo -e "${RED}ERROR: Script failed on line ${line_no} with exit code ${exit_code}.${NC}" >&2
  echo -e "${RED}Command: ${BASH_COMMAND}${NC}" >&2
  exit "$exit_code"
}
trap 'handle_error $LINENO' ERR

# --- Helper Functions ---

# Prints a message and exits with an error code.
die() {
  echo -e "${RED}ERROR: $1${NC}" >&2
  exit 1
}

# Normalizes an extension ID to lowercase for consistent matching.
normalize_id() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

# Retrieves metadata (id, pack, dependencies) from a package.json file.
get_ext_info() {
  local package_json="$1"
  local query="$2"
  # Exit successfully if jq fails, returning an empty string.
  jq -r "$query // [] | .[]" "$package_json" 2>/dev/null || true
}

# Finds the full path to an extension's folder by its ID.
# Uses a cache (__ext_folder_map) to avoid repeated slow lookups.
declare -A __ext_folder_map
find_extension_folder() {
  local ext_id_lower
  ext_id_lower=$(normalize_id "$1")

  if [[ -z "${__ext_folder_map[*]}" ]]; then
    for folder in "$EXT_DIR"/*; do
      if [[ -d "$folder" && -f "$folder/package.json" ]]; then
        # Extract publisher and name, then construct the ID.
        local manifest_id
        manifest_id=$(jq -r '.publisher + "." + .name' "$folder/package.json" 2>/dev/null || echo "")
        if [[ -n "$manifest_id" ]]; then
          __ext_folder_map["$(normalize_id "$manifest_id")"]="$folder"
        fi
      fi
    done
  fi
  echo "${__ext_folder_map[$ext_id_lower]:-}"
}

# --- Main Logic ---
main() {
  echo -e "${BLUE}=== VS Code Extensions Installer ===${NC}\n"

  declare -a deleted_extensions
  # --- 1. Setup and Validation ---
  command -v "$VSCODE" "${VSCODE_OPTIONS[@]}" >/dev/null || die "'$VSCODE' CLI not found. Please ensure it's in your PATH."
  command -v jq >/dev/null || die "'jq' is not installed. Please install it to parse extension data."
  [[ -f "$EXT_FILE" ]] || die "'$EXT_FILE' not found. Please create it."

  mkdir -p "$EXT_DIR"
  echo -e "${BLUE}Using local extensions directory: ${EXT_DIR}${NC}"

  # --- 2. Parse Input File ---
  declare -A top_level_extensions # Associative array for top-level extensions from the file.
  while IFS= read -r line; do
    # Skip comments and empty lines.
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$line" || "$line" == "//"* ]] && continue

    # Parse ID and pre-release flag.
    local ext_id="${line%%,*}"
    local flag="${line#*,}"
    local use_prerelease=""
    if [[ "$flag" == " USE-PRE-RELEASE" ]]; then
      use_prerelease="--pre-release"
    fi
    top_level_extensions["$ext_id"]="$use_prerelease"
  done <"$EXT_FILE"

  [[ ${#top_level_extensions[@]} -gt 0 ]] || die "No valid extensions found in '$EXT_FILE'."

  # --- 3. Pre-Install Snapshot ---
  echo -e "${BLUE}Getting list of currently installed extensions...${NC}"
  declare -A versions_before # Store versions before installing to track changes.
  while IFS='@' read -r id version; do
    versions_before["$(normalize_id "$id")"]="$version"
  done < <("$VSCODE" "${VSCODE_OPTIONS[@]}" --list-extensions --show-versions)

  # --- 4. Install Top-Level Extensions ---
  # This single loop installs or updates all explicitly requested extensions.
  # VS Code automatically handles fetching their dependencies.
  echo -e "${BLUE}Installing mandatory extensions from ${EXT_FILE}...${NC}"
  declare -a installation_results
  for ext_id in "${!top_level_extensions[@]}"; do
    local flag=${top_level_extensions[$ext_id]}
    local log_msg="Installing ${ext_id}..."
    [[ -n "$flag" ]] && log_msg="Installing ${ext_id} with pre-release..."
    echo -e "${BLUE}${log_msg}${NC}"

    # Capture output and status code.
    local output
    local rc
    set +e # Disable exit on error to capture status
    output=$("$VSCODE" "${VSCODE_OPTIONS[@]}" --install-extension "$ext_id" --force $flag 2>&1)
    rc=$?
    set -e # Re-enable exit on error

    if [[ $rc -ne 0 ]]; then
      echo -e "${RED}ERROR: Failed to install ${ext_id} (exit code: $rc)${NC}" >&2
      echo "Installation output:" >&2
      echo "$output" >&2
    else
      echo "$output"
      installation_results+=("$ext_id")
    fi
  done

  # --- 5. Discover All Required Extensions (Recursive) ---
  echo -e "\n${BLUE}Building complete set of needed extensions...${NC}"
  declare -A all_required_ids                      # The complete set of extensions that should be kept.
  declare -a queue=("${!top_level_extensions[@]}") # Start discovery with top-level extensions.
  declare -A processed_ids                         # Track processed IDs to avoid redundant work.

  while [[ ${#queue[@]} -gt 0 ]]; do
    local current_id="${queue[0]}"
    queue=("${queue[@]:1}") # Dequeue
    local current_id_lower
    current_id_lower=$(normalize_id "$current_id")

    [[ -n "${processed_ids[$current_id_lower]:-}" ]] && continue
    processed_ids["$current_id_lower"]=1
    all_required_ids["$current_id_lower"]=1

    local ext_folder
    ext_folder=$(find_extension_folder "$current_id")
    if [[ -z "$ext_folder" || ! -f "$ext_folder/package.json" ]]; then
      continue # Not installed or invalid, can't discover children.
    fi

    # Discover and enqueue pack members and dependencies.
    while IFS= read -r child_id; do [[ -n "$child_id" ]] && queue+=("$child_id"); done < <(get_ext_info "$ext_folder/package.json" '.extensionPack')
    while IFS= read -r child_id; do [[ -n "$child_id" ]] && queue+=("$child_id"); done < <(get_ext_info "$ext_folder/package.json" '.extensionDependencies')
  done

  # --- 6. Reconcile and Uninstall Orphans ---
  echo -e "\n${BLUE}Analyzing installed extensions for removal...${NC}"
  declare -a to_uninstall
  while IFS= read -r installed_id; do
    if [[ -z "${all_required_ids[$(normalize_id "$installed_id")]:-}" ]]; then
      to_uninstall+=("$installed_id")
    fi
  done < <("$VSCODE" "${VSCODE_OPTIONS[@]}" --list-extensions)

  for ext_id in "${to_uninstall[@]}"; do
    echo -e "${YELLOW}Uninstalling unneeded extension: $ext_id${NC}"
    # Use the VS Code CLI to uninstall correctly. This is the fix.
    if "$VSCODE" "${VSCODE_OPTIONS[@]}" --uninstall-extension "$ext_id" >/dev/null 2>&1; then
      deleted_extensions+=("$ext_id")
    else
      echo -e "${YELLOW}WARNING: Failed to uninstall $ext_id. It may be a dependency of another unmanaged extension.${NC}" >&2
    fi
  done

  # --- 7. Generate and Print Reports ---
  # Gather data from the final state of the extensions directory for accurate reporting.
  declare -A report_data        # id -> "version|status|type|parents"
  declare -A extension_packs    # pack_id -> members
  declare -A dependency_map     # parent_id -> dependencies
  declare -A pack_parents       # child_id -> pack_id
  declare -A dependency_parents # child_id -> parent_ids

  # Get final list of installed extensions and versions.
  declare -A versions_after
  while IFS='@' read -r id version; do
    versions_after["$(normalize_id "$id")"]="$version"
  done < <("$VSCODE" "${VSCODE_OPTIONS[@]}" --list-extensions --show-versions)

  # Build relationship maps (packs, dependencies) for reporting.
  for id_lower in "${!versions_after[@]}"; do
    local ext_folder
    ext_folder=$(find_extension_folder "$id_lower")
    [[ -z "$ext_folder" ]] && continue

    local pkg_json="$ext_folder/package.json"
    # This requires the original-cased ID, which we find from the list-extensions output.
    local original_id
    original_id=$("$VSCODE" "${VSCODE_OPTIONS[@]}" --list-extensions | grep -i "^${id_lower}$")

    # Map extension packs
    local members
    members=$(get_ext_info "$pkg_json" '.extensionPack')
    if [[ -n "$members" ]]; then
      extension_packs["$original_id"]="$members"
      while IFS= read -r member; do pack_parents["$(normalize_id "$member")"]="$original_id"; done <<<"$members"
    fi

    # Map dependencies
    local deps
    deps=$(get_ext_info "$pkg_json" '.extensionDependencies')
    if [[ -n "$deps" ]]; then
      dependency_map["$original_id"]="$deps"
      while IFS= read -r dep; do
        local dep_lower=$(normalize_id "$dep")
        local parents="${dependency_parents[$dep_lower]:-}"
        # Append parent, avoiding duplicates.
        if [[ ! "$parents" =~ (^|, )$original_id(,|$) ]]; then
          dependency_parents["$dep_lower"]="${parents:+$parents, }$original_id"
        fi
      done <<<"$deps"
    fi
  done

  # Print Hierarchies (matches original output)
  echo -e "\n${CYAN}=== EXTENSION PACKS HIERARCHY ===${NC}"
  if [[ ${#extension_packs[@]} -gt 0 ]]; then
    for parent in $(printf '%s\n' "${!extension_packs[@]}" | sort); do
      echo -e "\n${CYAN}📦 Extension Pack: $parent${NC}"
      while IFS= read -r member; do echo -e "  ├─ $member ${GREEN}[INSTALLED]${NC}"; done <<<"${extension_packs[$parent]}"
    done
  else
    echo -e "  ${YELLOW}No extension packs found${NC}"
  fi

  echo -e "\n${MAGENTA}=== DEPENDENCY HIERARCHY ===${NC}"
  if [[ ${#dependency_map[@]} -gt 0 ]]; then
    for parent in $(printf '%s\n' "${!dependency_map[@]}" | sort); do
      echo -e "\n${MAGENTA}🔗 $parent depends on:${NC}"
      while IFS= read -r dep; do echo -e "  ├─ $dep ${GREEN}[INSTALLED]${NC}"; done <<<"${dependency_map[$parent]}"
    done
  else
    echo -e "  ${YELLOW}No dependencies found${NC}"
  fi

  # Print Final Installation Summary Table
  echo -e "\n${GREEN}=== INSTALLATION RESULTS ===${NC}"
  printf "%-50s %-10s %-15s %-12s\n" "Extension ID" "Status" "Version" "Type"
  printf '%.0s=' {1..87}
  echo ""

  # Get sorted list of all final extensions
  mapfile -t sorted_ext_ids < <("$VSCODE" "${VSCODE_OPTIONS[@]}" --list-extensions | sort -f)

  for ext_id in "${sorted_ext_ids[@]}"; do
    local id_lower
    id_lower=$(normalize_id "$ext_id")
    local version="${versions_after[$id_lower]:-unknown}"
    local prev_version="${versions_before[$id_lower]:-}"

    local status="-"
    if [[ -z "$prev_version" ]]; then
      status="NEW"
    elif [[ "$version" != "$prev_version" ]]; then
      status="UPDATED"
    fi

    local type=""
    local parent_info=""
    if [[ -n "${top_level_extensions[$ext_id]:-}" ]]; then
      type="TOP-LEVEL"
    elif [[ -n "${pack_parents[$id_lower]:-}" ]]; then
      type="IN-PACK"
      parent_info="  └─ from pack: ${pack_parents[$id_lower]}"
    elif [[ -n "${dependency_parents[$id_lower]:-}" ]]; then
      type="IS-DEP"
      parent_info="  └─ needed by: ${dependency_parents[$id_lower]}"
    else
      # Should not happen in this logic, but as a fallback.
      type="UNKNOWN"
    fi

    printf "%-50s %-10s %-15s %-12s\n" "$ext_id" "$status" "$version" "$type"
    if [[ -n "$parent_info" ]]; then
      printf "%-50s %-10s %-15s %-12s\n" "$parent_info" "" "" ""
    fi
  done

  # Print deleted extensions
  if [[ ${#deleted_extensions[@]} -gt 0 ]]; then
    echo -e "\n${RED}Deleted Extensions (${#deleted_extensions[@]}):${NC}"
    printf '%.0s=' {1..87}
    echo ""
    for ext in "${deleted_extensions[@]}"; do
      printf '  %s\n' "$ext"
    done
  else
    echo -e "\n${GREEN}No extensions were deleted${NC}"
  fi

  # Save pretty-printed extensions.json
  if [[ -f "$EXT_DIR/extensions.json" ]]; then
    echo -e "\n${BLUE}Saving pretty-printed copy of extensions.json...${NC}"
    if jq '.' "$EXT_DIR/extensions.json" >"$EXT_DIR/extensions-pretty-printed.json"; then
      echo -e "${GREEN}Successfully saved $EXT_DIR/extensions-pretty-printed.json${NC}"
    else
      echo -e "${RED}WARNING: Failed to create pretty-printed copy of extensions.json${NC}" >&2
    fi
  fi

  echo -e "\n${GREEN}=== INSTALLATION COMPLETE ===${NC}"
  echo -e "${BLUE}Total needed extensions: ${#all_required_ids[@]}${NC}"
  echo -e "${BLUE}Extensions deleted: ${#deleted_extensions[@]}${NC}\n"
}

# --- Script Entry Point ---
main "$@"
