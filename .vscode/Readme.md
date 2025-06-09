# Guidelines for VS Code customisation and preferences files

## Shared project settings and preferences: `.vscode/`

- Use the `.vscode/` folder for all shared project setings that should remain consistent for all developers.

## Personal user settings and preferences: `.vscode-data-dir/User/`

- Use the `.vscode-data-dir/User/` folder for all personal customizations that should remain private for each inidvidual developer and that do not interfere with the project’s shared settings.

- For personal user preferences: Keep your custom `settings.json`, `keybindings.json` (and any other personal overrides) in the `User/` folder inside your "custom data directory" (`.vscode-data-dir/User/`).
