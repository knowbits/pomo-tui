# ==========================================================\
# Justfile for building and managing the Pomo-TUI project
# This file defines various tasks for building, testing, deploying, and running the project.
# Ensure you have the .NET SDK installed and available in your PATH.
# To use this Justfile, run `just <task>` in the terminal.
# ==========================================================\

# Define the .NET SDK version to use (optional, but good practice)
# DOTNET_SDK_VERSION := 8.0.100

# Define the target directory for build outputs
TARGET_DIR := "./target"

# Define the project file
PROJECT_FILE := "./pomo-tui.fsproj"

# The "default" target when running 'just' without arguments.
default: build


# Clean the build output directory
clean:
    @echo "Cleaning build outputs..."
    dotnet clean {{PROJECT_FILE}} --configuration Release
    rm -rf {{TARGET_DIR}}
    # mkdir -p {{TARGET_DIR}}
    @echo "Clean complete."


# Build a deployable self-contained binary into .target/ folder,
# for your platform's runtime with "Release" configuration, using the .NET SDK.
# NOTE: Add "--runtime linux-x64" to build for a specific runtime.
build: clean
    @echo "Building for linux-x64 (Release, self-contained)..."
    dotnet publish {{PROJECT_FILE}} --self-contained --configuration Release
    @echo "Build complete. Executable is in {{TARGET_DIR}}/pomo-tui"


# Tests the project using the .NET test runner.
# This command runs all tests defined in the project.
# test: build
#    @echo "Running tests..."
#    dotnet test {{PROJECT_FILE}}
#    @echo "Tests complete."


# Deploys the  ./target/pomo-tui binary to ~/.local/bin/
deploy-on-linux: build
    @echo "Installing pomo-tui to ~/.local/bin/..."
    sudo cp {{TARGET_DIR}}/pomo-tui ~/.local/bin/
    sudo chmod +x ~/.local/bin/pomo-tui
    @echo "Installation complete. You can now run 'pomo-tui'."

# For wuick testing during development.
# Build a debug version (not a single binary) and run it at the same time.
# Compiles the project as specified in 'pomo-tui.fsproj'.
# Builds to the default "debug output path", e.g. ./target/bin/Debug/net8.0/
run:
    @echo "Running application from source..."
    dotnet run --project {{PROJECT_FILE}}
    @echo "Application finished."
