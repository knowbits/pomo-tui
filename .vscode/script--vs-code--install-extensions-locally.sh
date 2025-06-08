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
# The script comprehensively tracks extension relationships:
# - TOP-LEVEL: Extensions explicitly listed in the .txt file
# - IN-PACK: Extensions that are part of extension packs
# - IS-DEP: Extensions that other extensions depend on (recursively)
#
# Any extension not in these categories will be removed.
# Only the latest version of each extension is kept.
#
set -euo pipefail

# Enhanced error handling
exec 2> >(tee -a >(logger -t "$(basename "$0")") >&2)

# Error trap: print detailed error information and abort
handle_error() {
    local exit_code=$?
    local line_no=$1
    echo "ERROR: Script failed at line $line_no with exit code $exit_code" >&2
    echo "Command: ${BASH_COMMAND}" >&2
    echo "Function stack: ${FUNCNAME[*]}" >&2
    exit $exit_code
}
trap 'handle_error $LINENO' ERR

# ANSI color definitions.
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"  # No Color

# Extension categorization
declare -A mandatory_extensions=()      # Extensions explicitly listed in .txt file
declare -A pack_member_extensions=()    # Extensions that are part of packs
declare -A dependency_extensions=()     # Extensions that other extensions depend on
declare -A all_needed_extensions=()     # Union of all above categories

# Relationship tracking
declare -A extension_packs=()           # parent -> pack members
declare -A extension_dependencies=()    # parent -> dependencies
declare -A dependency_parents=()        # dependency -> parents that need it
declare -A pack_parents=()             # pack member -> parent pack

# Installation tracking
declare -a installation_results=()
declare -a deleted_extensions=()

# Use VS Code Insiders CLI (change to "code" if needed)
VSCODE=code-insiders

# Get the full path of this script's folder
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Set the local extensions directory (absolute path)
EXT_DIR="${SCRIPT_DIR}/../.vscode-extensions"

# Set the path to the mandatory extensions file
EXT_FILE="${SCRIPT_DIR}/mandatory-extensions.txt"

# Function to trim whitespace from a string.
trim() {
    local input="$1"
    echo "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Function to normalize extension ID to lowercase
normalize_id() {
    local id="$1"
    echo "$id" | tr '[:upper:]' '[:lower:]'
}

# Function to get extension info from package.json
get_extension_info() {
    local package_json="$1"
    local info_type="$2"  # "pack", "dependencies", or "id"

    if [[ ! -f "$package_json" ]]; then
        return 1
    fi

    case "$info_type" in
        "pack")
            jq -r '.extensionPack // [] | .[]' "$package_json" 2>/dev/null || true
            ;;
        "dependencies")
            jq -r '.extensionDependencies // [] | .[]' "$package_json" 2>/dev/null || true
            ;;
        "id")
            jq -r '.publisher + "." + .name' "$package_json" 2>/dev/null || echo ""
            ;;
        *)
            echo "ERROR: Unknown info_type: $info_type" >&2
            return 1
            ;;
    esac
}

# Function to find extension folder by ID
find_extension_folder() {
    local ext_id="$1"
    local ext_id_lower
    ext_id_lower=$(normalize_id "$ext_id")

    for folder in "$EXT_DIR"/*; do
        if [[ -d "$folder" && -f "$folder/package.json" ]]; then
            local manifest_id
            manifest_id=$(normalize_id "$(get_extension_info "$folder/package.json" "id")")
            if [[ "$manifest_id" == "$ext_id_lower" ]]; then
                echo "$folder"
                return 0
            fi
        fi
    done
    return 1
}

# Function to get all versions of an extension and return the latest
get_latest_extension_version() {
    local ext_id="$1"
    local ext_id_lower
    ext_id_lower=$(normalize_id "$ext_id")

    local latest_version=""
    local latest_folder=""

    for folder in "$EXT_DIR"/*; do
        if [[ -d "$folder" ]]; then
            local folder_name
            folder_name=$(basename "$folder")
            # Extract extension ID from folder name (format: publisher.name-version)
            if [[ "$folder_name" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
                local folder_ext_id
                folder_ext_id=$(normalize_id "${BASH_REMATCH[1]}")
                local version="${BASH_REMATCH[2]}"
                if [[ "$folder_ext_id" == "$ext_id_lower" ]]; then
                    if [[ -z "$latest_version" ]] || [[ "$version" > "$latest_version" ]]; then
                        latest_version="$version"
                        latest_folder="$folder"
                    fi
                fi
            fi
        fi
    done

    if [[ -n "$latest_version" ]]; then
        echo "$latest_folder|$latest_version"
    fi
}

# Function to remove all versions of an extension except the latest
cleanup_old_versions() {
    local ext_id="$1"
    local ext_id_lower
    ext_id_lower=$(normalize_id "$ext_id")

    # Get the latest version info
    local latest_info
    latest_info=$(get_latest_extension_version "$ext_id")
    if [[ -z "$latest_info" ]]; then
        return 0
    fi

    IFS='|' read -r latest_folder latest_version <<< "$latest_info"

    # Remove all other versions
    for folder in "$EXT_DIR"/*; do
        if [[ -d "$folder" ]]; then
            local folder_name
            folder_name=$(basename "$folder")
            # Extract extension ID from folder name (format: publisher.name-version)
            if [[ "$folder_name" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+.*)$ ]]; then
                local folder_ext_id
                folder_ext_id=$(normalize_id "${BASH_REMATCH[1]}")
                local version="${BASH_REMATCH[2]}"
                if [[ "$folder_ext_id" == "$ext_id_lower" && "$folder" != "$latest_folder" ]]; then
                    echo -e "${YELLOW}  Removing old version: $(basename "$folder") (v$version)${NC}"
                    if ! rm -rf "$folder"; then
                        echo -e "${RED}ERROR: Failed to remove old version: $folder${NC}" >&2
                        return 1
                    fi
                fi
            fi
        fi
    done
}

# Function to install extension
install_extension() {
    local ext_id="$1"
    local extra_flag="$2"

    # Get version before installation (if extension exists)
    local previous_version
    previous_version=$("$VSCODE" --list-extensions --show-versions --extensions-dir "$EXT_DIR" \
        | grep -i "^$(normalize_id "$ext_id")@" | cut -d'@' -f2 || echo "")

    if [[ -n "$extra_flag" ]]; then
        echo -e "${BLUE}Installing ${ext_id} with pre-release...${NC}"
    else
        echo -e "${BLUE}Installing ${ext_id}...${NC}"
    fi

    # Capture all output from the installation command.
    local output
    local rc
    set +e  # Temporarily disable exit on error to capture the return code
    output=$("$VSCODE" --extensions-dir "$EXT_DIR" --install-extension "$ext_id" --force $extra_flag 2>&1)
    rc=$?
    set -e  # Re-enable exit on error

    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}ERROR: Failed to install ${ext_id} (exit code: $rc)${NC}" >&2
        echo "Installation output:" >&2
        echo "$output" >&2
        if echo "$output" | grep -q "v8::ToLocalChecked Empty MaybeLocal"; then
            echo -e "${RED}HINT: VS Code encountered a V8 error while processing $ext_id. This may indicate a bug in the extension or in VS Code. Try updating VS Code or check for known issues for this extension.${NC}" >&2
        fi
        return 1
    else
        echo "$output"
    fi

    # Retrieve the installed version.
    local installed_version
    installed_version=$("$VSCODE" --list-extensions --show-versions --extensions-dir "$EXT_DIR" \
        | grep -i "^$(normalize_id "$ext_id")@" | cut -d'@' -f2 || echo "unknown")

    # Determine status
    local status
    if [[ -z "$previous_version" ]]; then
        status="NEW"
    elif [[ "$previous_version" != "$installed_version" ]]; then
        status="UPDATED"
    else
        status="-"
    fi

    installation_results+=("$ext_id|$status|$installed_version")

    # Clean up old versions after installation
    cleanup_old_versions "$ext_id"
}

# Function to analyze all installed extensions to build complete relationship map
analyze_all_installed_extensions() {
    echo -e "${BLUE}Analyzing all installed extensions for relationships...${NC}"

    # Clear previous relationship data
    extension_packs=()
    extension_dependencies=()
    dependency_parents=()
    pack_parents=()

    # Get all installed extensions
    local -a all_installed=()
    while IFS= read -r ext_id; do
        all_installed+=("$ext_id")
    done < <("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR")

    echo -e "${BLUE}Found ${#all_installed[@]} installed extensions${NC}"

    # Process each installed extension
    for ext_id in "${all_installed[@]}"; do
        local ext_folder
        if ext_folder=$(find_extension_folder "$ext_id"); then
            local package_json="$ext_folder/package.json"

            if [[ -f "$package_json" ]]; then
                # Check for extension packs
                local pack_members=()
                while IFS= read -r member; do
                    if [[ -n "$member" ]]; then
                        pack_members+=("$member")
                    fi
                done < <(get_extension_info "$package_json" "pack")

                if [[ ${#pack_members[@]} -gt 0 ]]; then
                    extension_packs["$ext_id"]=$(printf "%s\n" "${pack_members[@]}")
                    echo -e "${CYAN}Found extension pack: $ext_id with ${#pack_members[@]} members${NC}"

                    for member in "${pack_members[@]}"; do
                        local member_normalized
                        member_normalized=$(normalize_id "$member")
                        pack_member_extensions["$member_normalized"]=1
                        all_needed_extensions["$member_normalized"]=1
                        pack_parents["$member_normalized"]="$ext_id"
                    done
                fi

                # Check for dependencies
                local deps=()
                while IFS= read -r dep; do
                    if [[ -n "$dep" ]]; then
                        deps+=("$dep")
                    fi
                done < <(get_extension_info "$package_json" "dependencies")

                if [[ ${#deps[@]} -gt 0 ]]; then
                    extension_dependencies["$ext_id"]=$(printf "%s\n" "${deps[@]}")
                    echo -e "${MAGENTA}Found dependencies for $ext_id: ${#deps[@]} dependencies${NC}"

                    for dep in "${deps[@]}"; do
                        local dep_normalized
                        dep_normalized=$(normalize_id "$dep")
                        dependency_extensions["$dep_normalized"]=1
                        all_needed_extensions["$dep_normalized"]=1

                        # Track parent relationship
                        if [[ -n "${dependency_parents[$dep_normalized]:-}" ]]; then
                            dependency_parents["$dep_normalized"]+=", $ext_id"
                        else
                            dependency_parents["$dep_normalized"]="$ext_id"
                        fi
                    done
                fi
            else
                echo -e "${YELLOW}WARNING: No package.json found for $ext_id in $ext_folder${NC}"
            fi
        else
            echo -e "${YELLOW}WARNING: Could not find folder for installed extension: $ext_id${NC}"
        fi
    done
}

# Function to print extension pack hierarchy
print_extension_packs() {
    echo -e "\n${CYAN}=== EXTENSION PACKS HIERARCHY ===${NC}"

    local found_packs=false
    for parent in "${!extension_packs[@]}"; do
        found_packs=true
        echo -e "\n${CYAN}📦 Extension Pack: $parent${NC}"
        while IFS= read -r member; do
            if [[ -n "$member" ]]; then
                local member_status=""
                local member_normalized
                member_normalized=$(normalize_id "$member")

                # Check if this member is actually installed
                local is_installed
                is_installed=$("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR" | grep -i "^$member_normalized$" || echo "")

                if [[ -n "$is_installed" ]]; then
                    member_status="[INSTALLED]"
                else
                    member_status="[NOT INSTALLED]"
                fi

                echo -e "  ├─ $member ${GREEN}$member_status${NC}"
            fi
        done <<< "${extension_packs[$parent]}"
    done

    if [[ "$found_packs" == false ]]; then
        echo -e "  ${YELLOW}No extension packs found${NC}"
    fi
}

# Function to print dependency hierarchy
print_dependency_hierarchy() {
    echo -e "\n${MAGENTA}=== DEPENDENCY HIERARCHY ===${NC}"

    local found_deps=false
    for parent in "${!extension_dependencies[@]}"; do
        found_deps=true
        echo -e "\n${MAGENTA}🔗 $parent depends on:${NC}"
        while IFS= read -r dep; do
            if [[ -n "$dep" ]]; then
                local dep_status=""
                local dep_normalized
                dep_normalized=$(normalize_id "$dep")

                # Check if this dependency is actually installed
                local is_installed
                is_installed=$("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR" | grep -i "^$dep_normalized$" || echo "")

                if [[ -n "$is_installed" ]]; then
                    dep_status="[INSTALLED]"
                else
                    dep_status="[NOT INSTALLED]"
                fi

                echo -e "  ├─ $dep ${GREEN}$dep_status${NC}"
            fi
        done <<< "${extension_dependencies[$parent]}"
    done

    if [[ "$found_deps" == false ]]; then
        echo -e "  ${YELLOW}No dependencies found${NC}"
    fi
}

# Function to print simplified installation results
print_simplified_installation_results() {
    echo -e "\n${GREEN}=== INSTALLATION RESULTS ===${NC}"

    # Create a combined array with all extensions and their info
    declare -A all_extensions=()
    declare -A ext_status=()
    declare -A ext_version=()
    declare -A ext_type=()
    declare -A ext_parent=()

    # Process installation results
    for result in "${installation_results[@]}"; do
        IFS='|' read -r id status version <<< "$result"
        local id_normalized
        id_normalized=$(normalize_id "$id")
        all_extensions["$id_normalized"]="$id"
        ext_status["$id_normalized"]="$status"
        ext_version["$id_normalized"]="$version"
    done

    # Also include any other installed extensions that weren't in installation_results
    while IFS= read -r ext_id; do
        local ext_id_normalized
        ext_id_normalized=$(normalize_id "$ext_id")
        if [[ -z "${all_extensions[$ext_id_normalized]:-}" ]]; then
            all_extensions["$ext_id_normalized"]="$ext_id"
            ext_status["$ext_id_normalized"]="-"
            # Get version
            local version
            version=$("$VSCODE" --list-extensions --show-versions --extensions-dir "$EXT_DIR" \
                | grep -i "^$ext_id_normalized@" | cut -d'@' -f2 || echo "unknown")
            ext_version["$ext_id_normalized"]="$version"
        fi
    done < <("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR")

    # Determine types and parents
    for ext_id_normalized in "${!all_extensions[@]}"; do
        if [[ -n "${mandatory_extensions[$ext_id_normalized]:-}" ]]; then
            ext_type["$ext_id_normalized"]="TOP-LEVEL"
            ext_parent["$ext_id_normalized"]=""
        elif [[ -n "${pack_member_extensions[$ext_id_normalized]:-}" ]]; then
            ext_type["$ext_id_normalized"]="IN-PACK"
            ext_parent["$ext_id_normalized"]="  └─ from pack: ${pack_parents[$ext_id_normalized]:-unknown}"
        elif [[ -n "${dependency_extensions[$ext_id_normalized]:-}" ]]; then
            ext_type["$ext_id_normalized"]="IS-DEP"
            ext_parent["$ext_id_normalized"]="  └─ needed by: ${dependency_parents[$ext_id_normalized]:-unknown}"
        else
            ext_type["$ext_id_normalized"]="UNKNOWN"
            ext_parent["$ext_id_normalized"]=""
        fi
    done

    # Sort extensions alphabetically
    local -a sorted_extensions=()
    while IFS= read -r ext_id_normalized; do
        sorted_extensions+=("$ext_id_normalized")
    done < <(printf '%s\n' "${!all_extensions[@]}" | sort)

    # Print header
    printf "%-50s %-10s %-15s %-12s\n" "Extension ID" "Status" "Version" "Type"
    printf '%.0s=' {1..87}; echo ""

    # Print extensions
    for ext_id_normalized in "${sorted_extensions[@]}"; do
        local ext_id="${all_extensions[$ext_id_normalized]}"
        local status="${ext_status[$ext_id_normalized]}"
        local version="${ext_version[$ext_id_normalized]}"
        local type="${ext_type[$ext_id_normalized]}"
        local parent="${ext_parent[$ext_id_normalized]}"

        # Print plain type (no color)
        printf "%-50s %-10s %-15s %-12s\n" "$ext_id" "$status" "$version" "$type"

        # Print parent info if available
        if [[ -n "$parent" ]]; then
            printf "%-50s %-10s %-15s %-12s\n" "$parent" "" "" ""
        fi
    done
}

# Main execution starts here
echo -e "${BLUE}=== VS Code Extensions Installer ===${NC}\n"

# Verify that the VS Code CLI exists.
if ! command -v "$VSCODE" >/dev/null 2>&1; then
    echo -e "${RED}ERROR: VS Code CLI ('$VSCODE') not found in PATH${NC}" >&2
    echo "Please ensure VS Code is installed and the CLI is available" >&2
    exit 1
fi

# Create the local extensions directory if it doesn't exist.
if ! mkdir -p "$EXT_DIR"; then
    echo -e "${RED}ERROR: Could not create directory ${EXT_DIR}${NC}" >&2
    exit 1
fi
echo -e "${BLUE}Using local extensions directory: ${EXT_DIR}${NC}"

# Ensure that the mandatory file exists.
if [[ ! -f "$EXT_FILE" ]]; then
    echo -e "${RED}ERROR: ${EXT_FILE} not found! Please create this file with the extension IDs.${NC}" >&2
    exit 1
fi

# Read lines from the mandatory extensions file
declare -a ext_lines=()
while IFS= read -r line; do
    trimmed=$(trim "$line")
    if [[ -z "$trimmed" || "$trimmed" == "//"* ]]; then
        continue
    fi
    ext_lines+=( "$trimmed" )
done < "$EXT_FILE"

if [[ ${#ext_lines[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR: No valid extensions found in ${EXT_FILE}${NC}" >&2
    exit 1
fi

# Build mandatory extensions set
for entry in "${ext_lines[@]}"; do
    ext_id=""
    if [[ "$entry" == *","* ]]; then
        IFS=',' read -r raw_ext _ <<< "$entry"
        ext_id=$(trim "$raw_ext")
    else
        ext_id=$(trim "$entry")
    fi
    key=$(normalize_id "$ext_id")
    mandatory_extensions["$key"]=1
    all_needed_extensions["$key"]=1
done

echo -e "${BLUE}Installing mandatory extensions from ${EXT_FILE}...${NC}"

# Install mandatory extensions
for entry in "${ext_lines[@]}"; do
    ext_id=""
    flag=""
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

# CRITICAL: Analyze all installed extensions AFTER installation is complete
analyze_all_installed_extensions

# Get list of all currently installed extensions
echo -e "\n${BLUE}Analyzing installed extensions...${NC}"
declare -a all_installed=()
while IFS= read -r line; do
    all_installed+=( "$line" )
done < <("$VSCODE" --list-extensions --extensions-dir "$EXT_DIR")

# Identify extensions to delete (not in any needed category)
for ext in "${all_installed[@]}"; do
    ext_normalized=$(normalize_id "$ext")
    if [[ -z "${all_needed_extensions[$ext_normalized]:-}" ]]; then
        echo -e "${YELLOW}Marking for deletion: $ext (not needed)${NC}"
        deleted_extensions+=("$ext")
        if ! "$VSCODE" --extensions-dir "$EXT_DIR" --uninstall-extension "$ext" 2>/dev/null; then
            echo -e "${YELLOW}WARNING: Failed to uninstall $ext (may not be critical)${NC}" >&2
        fi
    fi
done

# Clean up old versions for all remaining extensions
echo -e "\n${BLUE}Cleaning up old versions...${NC}"
for ext in "${all_installed[@]}"; do
    ext_normalized=$(normalize_id "$ext")
    if [[ -n "${all_needed_extensions[$ext_normalized]:-}" ]]; then
        cleanup_old_versions "$ext"
    fi
done

# ---------------------------------------------------------------
# Print comprehensive summary with relationships

# Print extension packs hierarchy
print_extension_packs

# Print dependency hierarchy
print_dependency_hierarchy

# Print simplified installation results
print_simplified_installation_results

# Print deleted extensions
if [[ ${#deleted_extensions[@]} -gt 0 ]]; then
    echo -e "\n${RED}Deleted Extensions (${#deleted_extensions[@]}):${NC}"
    for ext in "${deleted_extensions[@]}"; do
        echo "  $ext"
    done
else
    echo -e "\n${GREEN}No extensions were deleted${NC}"
fi

# Save a pretty-printed copy of extensions.json if it exists
if [[ -f "$EXT_DIR/extensions.json" ]]; then
    echo -e "\n${BLUE}Saving pretty-printed copy of extensions.json...${NC}"
    if jq '.' "$EXT_DIR/extensions.json" > "$EXT_DIR/extensions-pretty-printed.json"; then
        echo -e "${GREEN}Successfully saved $EXT_DIR/extensions-pretty-printed.json${NC}"
    else
        echo -e "${RED}ERROR: Failed to create pretty-printed copy of extensions.json${NC}" >&2
    fi
fi

echo -e "\n${GREEN}=== INSTALLATION COMPLETE ===${NC}"
echo -e "${BLUE}Total needed extensions: ${#all_needed_extensions[@]}${NC}"
echo -e "${BLUE}Extensions deleted: ${#deleted_extensions[@]}${NC}\n"
