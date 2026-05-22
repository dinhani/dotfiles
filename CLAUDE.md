# Project

Two independent automations for setting up and maintaining a personal/work development machine.

## Goal 1: Dotfiles backup & restore (`dotfiles.py` + `dotfiles_tui.py`)

Cross-platform (Windows / Linux / Mac) Python script that backs up app config files into the `dotfiles/` directory and restores them back to their OS-specific locations.

### Module split

- `dotfiles.py` — **core / domain**: file-copy primitives, OS dispatch, the `Op` enum (`BACKUP` / `RESTORE`), per-app `backup_<app>` / `restore_<app>` functions, the `ITEMS` registry, and `__main__`.
- `dotfiles_tui.py` — **UI only**: `show_tui(items, panels)`, a generic two-panel picker built on vendored `prompt_toolkit`. Knows nothing about backup/restore — it takes the two panel labels as a parameter and returns `(panel_label, item_name)` tuples. The TUI never imports from `dotfiles.py` (avoids a cycle); the caller maps panel labels back to `Op` via `Op(label)`.

### Core (`dotfiles.py`)

- Entry point. Calls `show_tui(ITEMS, (Op.BACKUP, Op.RESTORE))`, then dispatches `fns[name][Op(label)]()`.
- Each app has a `backup_<app>` and `restore_<app>` pair, decorated with `@operation("AppName", "subdir")` which injects the app name and resolved `dotfiles/<subdir>` path.
- Path operations use the `File` class (subclass of `pathlib.Path`) with a `>>` operator: `source >> target` copies file or directory. First write into a `dotfiles/<app>/` subtree deletes that subtree once per session to avoid stale files.
- OS dispatch uses `match SYSTEM` against the `OS` StrEnum (`WIN`, `MAC`, `LINUX`). Unsupported combos call `log_unsupported(app)`.
- `Op` is a `StrEnum` (`BACKUP = "Backup"`, `RESTORE = "Restore"`) — values double as the user-facing panel labels.
- Registry: `ITEMS: dict[str, dict[str, dict[Op, Callable[[], None]]]]` — `category → name → {Op.BACKUP: fn, Op.RESTORE: fn}`. Add new apps there.
- Path constants: `WIN_HOME`, `WIN_ROAMING`, `WIN_LOCAL`, `UNIX_HOME`, `MAC_APP_SUPPORT`, `DOTFILES`.
- Dependencies are vendored under `vendor/` and added to `sys.path` at import time.

### TUI (`dotfiles_tui.py`)

- `show_tui(items, panels)` — generic two-panel picker. `panels` is a `tuple[str, str]` of left/right labels; the function has no knowledge of the domain those labels represent.
- Keyboard: `Tab` / `←` / `→` switches panel · `↑` / `↓` moves cursor (skips category headers) · `Space` toggles · `a` selects all · `n` clears all · `Enter` confirms · `Esc` / `Ctrl-C` cancels.
- Returns `list[tuple[str, str]]` of `(panel_label, item_name)` in menu order, left-panel picks before right-panel picks.

### Adding a new app
1. Write `backup_<app>` and `restore_<app>` in `dotfiles.py`, both decorated with `@operation("Display Name", "subdir")`.
2. Handle each `OS` case explicitly; use `log_unsupported(app)` for unsupported platforms.
3. Register in `ITEMS` under a category (`Terminal`, `Editor`, `Notes`, ...) as `"Name": {Op.BACKUP: backup_<app>, Op.RESTORE: restore_<app>}`.

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

## JetBrains consistency rules

Files live under `dotfiles/jetbrains/<IDE>/{keymaps,options}/`. When auditing or modifying them, enforce:

1. **Keymaps: Windows ↔ macOS must mirror each other.** The Windows keymap (`VSCode copy.xml`) and macOS keymap (`VSCode _macOS_ copy.xml`) for the same IDE must define the same set of action IDs with the same letter/digit key — only the modifiers differ. Translation: Windows `ctrl` → macOS `meta`, `shift` → `shift`, `alt` → `meta`. Example: Windows `ctrl t` ↔ macOS `meta t`; Windows `shift ctrl o` ↔ macOS `shift meta o`.
2. **Options (and keymaps) must be consistent across all IDEs, except DataGrip and DataSpell.** Every option file (`advancedSettings.xml`, `colors.scheme.xml`, `editor-font.xml`, `ide.general.xml`, `laf.xml`, `projectView.xml`, `ui.lnf.xml`) and both keymap files should be byte-identical across all JetBrains IDEs. **DataGrip** (databases) and **DataSpell** (data analysis) are allowed to diverge for data/DB-specific configuration and shortcuts — don't force them to match the others.
3. **Reference IDE: IntelliJIdea.** When fixing drift among the non-data IDEs, align to IntelliJ's version.
