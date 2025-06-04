# pomo-tui - A terminal based TUI for The Pomodoro Technique

## Installation

1. Install the DotNet SDK 8.0 on Ubuntu:
  - `sudo apt update`
  - `sudo apt install dotnet-sdk-8.0`
  - NOTE: it requires ~ 450MB (as of May 2025)

2. Clone this repository:
  - `git clone https://github.com/knowbits/pomo-tui.git`

3. In the repository, run these commands:
  ```bash
  # First publish to a local directory
  dotnet publish --runtime linux-x64 --self-contained --configuration Release -p:PublishSingleFile=true --output ./publish/

  # Then copy the binary to ~/.local/bin with correct permissions
  sudo cp ./publish/pomo-tui ~/.local/bin/
  sudo chmod +x ~/.local/bin/pomo-tui
  ```
4. Run `pomo-tui` to verify that the TUI has been installed and is in `$PATH`

## Usage

- Run `pomo-tui` to start the TUI
  - A menu of all the available keyboard **commands** will be shown in the Terminal window.

- Command-line options to `pomo-tui`:
  - `--sound-alert`         : Enable sound alerts (Is OFF by default)
  - `--task-length-min [n]` : Set the work session length to *n* minutes (default is 25)
  - `--break-length-min [n]`: Set the break length to *n* minutes (default is 5)


## Concepts

- See the comment block in `Program.fs` for further explanations of the TUI.
