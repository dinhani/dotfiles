# Project

Two independent automations for setting up and maintaining a personal/work development machine.

## Goal 1: Dotfiles backup & restore (`dotfiles.py`)

Cross-platform (Windows / Linux / Mac) Python script that backs up app config files into the `dotfiles/` directory and restores them back to their OS-specific locations.

- Entry point: `dotfiles.py` (interactive checkbox menu via `InquirerPy`).
- Each app has a `backup_<app>` and `restore_<app>` pair, decorated with `@operation("AppName", "subdir")` which injects the app name and resolved `dotfiles/<subdir>` path.
- Path operations use the `File` class (subclass of `pathlib.Path`) with a `>>` operator: `source >> target` copies file or directory. First write into a `dotfiles/<app>/` subtree deletes that subtree once per session to avoid stale files.
- OS dispatch uses `match SYSTEM` against the `OS` StrEnum (`WIN`, `MAC`, `LINUX`). Unsupported combos call `log_unsupported(app)`.
- Registry of all apps lives in the `ITEMS` dict at the bottom — add new apps there.
- Path constants: `WIN_HOME`, `WIN_ROAMING`, `WIN_LOCAL`, `UNIX_HOME`, `MAC_APP_SUPPORT`, `DOTFILES`.
- Dependencies are vendored under `vendor/` and added to `sys.path` at import time.

### Adding a new app
1. Write `backup_<app>` and `restore_<app>`, both decorated with `@operation("Display Name", "subdir")`.
2. Handle each `OS` case explicitly; use `log_unsupported(app)` for unsupported platforms.
3. Register in `ITEMS` with a category (`Terminal`, `Editor`, `Notes`, ...).

## Goal 2: Unix machine setup (`setup-unix.sh` + `setup-unix-functions.sh`)

Idempotent provisioning script for fresh Linux / Mac machines. Installs shells, build tools, CLI tools, language runtimes, editors and extensions, and writes shell config files.

- Entry point: `setup-unix.sh`. Requires `EMAIL` env var (used for git, GPG, SSH).
- Helpers live in `setup-unix-functions.sh` and are sourced at the top.
- Platform detection: `is_linux`, `is_mac`, `is_mac_intel`, `is_mac_arm`. Account type: `is_personal` (when `EMAIL == renatodinhani@gmail.com`) vs `is_work`.
- Idempotent install wrappers: `install_apt`, `install_brew`, `install_asdf <lang> <version>`, `install_mas`, `install_vscode <ext>` (installs for both `code` and `cursor` if present). All check first and call `log_skip` if already installed.
- Writes `~/.shell_common`, `~/.bash_profile`, `~/.bashrc`, `~/.zshrc` via heredocs. `~/.shell_common` is sourced by both shells; `~/.shell_private` is optional.
- Dirs: `~/downloads`, `~/scripts`, `~/tools`, `~/projects` (constants in functions file).
- Logging: `log` (blue), `log_skip` (yellow), both to stderr with timestamp.
- `brew_dir` returns the Homebrew prefix per platform (`/usr/local`, `/opt/homebrew`, `/home/linuxbrew/.linuxbrew`).

### Adding a new tool
- CLI tool: `install_brew <name>` in the CLI tools section. Put OS-specific tools inside `is_linux` / `is_mac` blocks.
- Language: `install_asdf <lang> <version>`.
- VSCode/Cursor extension: `install_vscode <publisher.name>`.
- App Store (Mac): `install_mas <id>`.
- For tools not available via a package manager, follow the "pre-compiled tools" / "local compiled tools" patterns at the bottom of `setup-unix.sh` (download + `cp` to `$DIR_TOOLS`, or `git clone` + `make`).

## Conventions

- No Windows setup script — only dotfiles backup/restore covers Windows.
- Bash uses Unix syntax (forward slashes, `/dev/null`).
- Keep operations idempotent: every install path must check first and skip if already present.
