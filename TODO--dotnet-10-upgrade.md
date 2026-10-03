# TODO — upgrade pomo-tui to .NET 10

Current: SDK pinned to `9.0.318` in `mise.toml`, `<TargetFramework>net9.0</TargetFramework>` in
`pomo-tui.fsproj`. Newest stable SDK when written: `10.0.401` (11.0 is preview only — do not use).
.NET 10 is the LTS line; .NET 9 is STS and reaches end of support earlier — check
https://dotnet.microsoft.com/platform/support/policy/dotnet-core before deciding the timing.

## Change set

- [ ] `mise.toml`: `dotnet = "10.0.<latest 10.0.x>"` (`mise ls-remote dotnet | rg '^10\.0\.'`).
- [ ] `pomo-tui.fsproj`: `net9.0` -> `net10.0`.
- [ ] `Justfile`: update the `DOTNET_SDK_VERSION` comment.
- [ ] `Readme.md`: install step still says `dotnet-sdk-9.0` (apt); change to the 10.0 package / mise.

## Things to check (caveats)

- **Bare-shell/AI sessions:** the SDK comes from mise, not apt/`~/.dotnet`. Confirm `dotnet --version`
  in `env -i HOME=$HOME PATH=$HOME/.local/share/mise/shims:$HOME/.local/bin:$HOME/.cargo/bin:/usr/bin:/bin`.
  If both an apt SDK and the mise SDK exist, the mise shim wins only when it is first on PATH.
- **`global.json`:** none exists today. If one is ever added it must match the pinned SDK
  (or use `rollForward`), otherwise builds fail with "requested SDK not found".
- **F# compiler / FSharp.Core:** the SDK bundles a newer F# (F# 10). Rebuild and read new warnings
  (nullness, stricter analyzers); `--warnaserror` is not set, so warnings will not fail the build silently.
- **Fantomas (`.config/dotnet-tools.json`, currently 7.0.2):** run `dotnet tool restore`, then
  `just` format recipe; a newer Fantomas may reformat the whole file. Check for a release that
  supports the F# 10 syntax and bump it in the same change.
- **Packages:** `Spectre.Console 0.50.0` and `FSharp.SystemTextJson 1.4.36` — verify each has a
  net10-compatible release and that `System.Text.Json` (now inbox 10.x) behaviour is unchanged for
  the JSON files the app reads/writes (round-trip a real state file before and after).
- **Publish:** `PublishSingleFile` + `dotnet publish --runtime linux-x64 --self-contained` — re-test the
  published binary starts on a machine without the SDK; check the output size and whether
  `--self-contained` needs `-p:PublishSingleFile=true` explicitly with the new SDK.
- **Build outputs:** `Directory.Build.props` redirects `obj/` and `bin/` under `target/`; confirm the
  new SDK still honours it (a stale `target/obj` from net9.0 should be deleted first).
- **CI/other hosts:** any runner, container image, or install script that installs .NET 9 must move too
  (none known in this repo; grep the wider fleet before closing).
- **Rollback:** revert the three lines above; delete `target/` and rerun `dotnet restore`.

## Verify when done

- `just --evaluate` exits 0, `just` build/publish recipes succeed, `dotnet --version` prints the pin,
  the published binary runs, `dotnet tool run fantomas --check .` is clean.
