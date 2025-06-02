# pomo-tui - A terminal based TUI for The Pomodoro Technique

## Installation

0. Install the DotNet SDK 8.0 on Ubuntu:
  - `sudo apt update`
  - `sudo apt install dotnet-sdk-8.0`
  - NOTE: it requires ~ 450MB (as of May 2025)

1. Clone this repository:
  - `git glone https://github.com/knowbits/pomo-tui.git`

2. In the repository, run `$ dotnet publish --runtime linux-x64 --self-contained --configuration Release --output ~/.local/bin/pomo-tui/`
3. Add `~/.local/bin/pomo-tui/` to `$PATH` in `~/.bashrc` by adding this line:
  - `export PATH="$HOME/.local/bin/pomo-tui:$PATH"`

4. Run `source ~/.bashrc` to update `$PATH`
5. Run `pomo-tui` to verify that the TUI has been installed and is in `$PATH`

## Usage

- Run `pomo-tui` to start the TUI
  - A menu of all the available keyboard **commands** will be shown in the Terminal window.

- Command-line options to `pomo-tui`:
  - `--sound-alert`         : Enable sound alerts (Is OFF by default)
  - `--task-length-min [n]` : Set the work session length to *n* minutes (default is 25)
  - `--break-length-min [n]`: Set the break length to *n* minutes (default is 5)


## Concepts

- See the comment block in `Program.fs` for further explanations of the TUI.


