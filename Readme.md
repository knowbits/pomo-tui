# pomo-tui - A terminal utility for "The Pomodoro Technique"

> Inspired by the "pomodori-cli" (pom) CLI utility by NRK.no

> Repo: <https://github.com/nrkno/pomodoro-cli>


## Installation

### Ubuntu

1. Install "DotNet SDK" version 8.0 on Ubuntu:
  - `sudo apt update`
  - `sudo apt install dotnet-sdk-8.0`
  - NOTE: The installation requires ~ 450MB.

2. Clone this repository:
  - `git clone https://github.com/knowbits/pomo-tui.git`

3. In the local repository, run these commands:

  ```bash
  # 1. Publish the binary to the ./target/ folder
  dotnet publish --runtime linux-x64 --self-contained --configuration Release --output ./target/

  # 2. Copy the binary to ~/.local/bin/ and set executable permissions
  sudo cp ./target/pomo-tui ~/.local/bin/
  sudo chmod +x ~/.local/bin/pomo-tui
  ```

## Usage

- Run `pomo-tui` in a terminal to start the Pomodoro TUI
  - A menu of all the available keyboard **commands** will be shown in the terminal.

- Command-line options to `pomo-tui`:
  - `--sound-alert`         : Enable sound alerts (Is OFF by default)
  - `--task-length-min [n]` : Set the Pomodoro session length to *n* minutes (default is 25)
  - `--break-length-min [n]`: Set the break length to *n* minutes (default is 5)


## Concepts

- See the comment block in [Program.fs](./Program.fs) for further explanations of the terminal app.
