# ==========================================================\
# Justfile for building and managing the Pomo-TUI project
# This file defines various tasks for building, testing, deploying, and running the project.
# Ensure you have the .NET SDK installed and available in your PATH.
# To use this Justfile, run `just <task>` in the terminal.
# ==========================================================\

# Define the .NET SDK version to use (optional, but good practice)
# DOTNET_SDK_VERSION := 9.0.301

# Define the target directory for build outputs
TARGET_DIR := "./target"

# Define the project file
PROJECT_FILE := "./pomo-tui.fsproj"

# Example output: "Linux-x64"
PLATFORM := `dotnet --info | awk -F': ' '/OS Platform:/ {os=$2} /Architecture:/ {arch=$2} END {print os "-" arch}'`


# ==========================================================
# Targets: default, help
# ==========================================================

# The "default" target when running 'just' without arguments.
default: build

# Print description of each target
help:
    @just --list


# ==========================================================
# Targets related to the VS Code development environment.
# Install .NET local tools, format F# source code files etc.
# ==========================================================

# Initialise dev. env. by installing all ".NET local tools" listed in .configure/dotnet-tools.json file.
init-dev-env:
    @echo "Initializing development environment..."
    @echo "Installing the 'Fantomas' formatter locally (for Ionode F# plugin)..."
    dotnet tool restore
    @echo "Development environment initialized."


# Formats all F# source files using Fantomas
format: init-dev-env
    @echo "Formatting F# source files with Fantomas..."
    dotnet tool run fantomas .
    @echo "Formatting complete."


# ==========================================================
# Build, test and deploy targets for the F# project
# This section contains commands to build, clean, and test the project.
# ==========================================================

# Clean the build output directory (.target/
clean:
    @echo "Cleaning build outputs..."
    # dotnet clean {{ PROJECT_FILE }} --configuration Release
    rm -rf {{ TARGET_DIR }}
    @if [ -d {{ TARGET_DIR }} ]; then \
        echo "WARNING: {{ TARGET_DIR }} could not be fully removed. Make sure no process is using it."; \
        lsof +D {{ TARGET_DIR }} || true; \
    fi
    # mkdir -p {{ TARGET_DIR }}
    @echo "Clean complete."


# Runs all tests defined in the project using the ".NET test runner".
# test:
#    @echo "Running tests..."
#    dotnet test {{PROJECT_FILE}}
#    @echo "Tests complete."


# Initializes all NuGet dependencies as specified in the ".fsproj" file
init:
    @echo "Restoring NuGet packages for the F# project..."
    dotnet restore {{ PROJECT_FILE }}
    @echo "NuGet dependencies initialized."


# Build a deployable self-contained binary into .target/ folder, for your platform's runtime with "Release" configuration, using the .NET SDK.
build: init
    @echo "Building for platform '{{PLATFORM}}' ('Release' configuration, self-contained)..."
    dotnet publish {{ PROJECT_FILE }} --self-contained --configuration Release
    # NOTE: Instead add option "--runtime linux-x64" to build for a specific runtime.
    @echo "Built the single-file binary: '{{ TARGET_DIR }}/pomo-tui'"


# Deploys the  ./target/pomo-tui binary to ~/.local/bin/
deploy-on-linux: build
    @echo "Copying './target/pomo-tui' to '~/.local/bin/pomo-tui'..."
    sudo cp {{ TARGET_DIR }}/pomo-tui ~/.local/bin/
    sudo chmod +x ~/.local/bin/pomo-tui
    @echo "You can now run 'pomo-tui'."


# Build and run a "debug version" (in folder './target/bin/Debug/net9.0/')
run: init
    @echo "Building and Running application from source..."
    dotnet run --project {{ PROJECT_FILE }}
    @echo "Application finished."
