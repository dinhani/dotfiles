# Project

Two independent automations for setting up and maintaining a personal/work development machine.

## Goal 1: Dotfiles backup & restore (`dotfiles.py` + `dotfiles_tui.py`)

Cross-platform (Windows / Linux / Mac) Python script that backs up app config files into the `dotfiles/` directory and restores them back to their OS-specific locations.

### Module split

- `dotfiles.py` — core/domain: file-copy primitives, OS dispatch, per-app backup/restore handlers, and the registry mapping categories → apps → handlers.
- `dotfiles_tui.py` — UI only: a generic two-panel picker built on vendored `prompt_toolkit`. Knows nothing about backup/restore — it takes panel labels as a parameter and returns `(panel_label, item_name)` selections. The TUI never imports from `dotfiles.py` (avoids a cycle).

### Core (`dotfiles.py`)

- Each app has a backup/restore pair decorated with `@operation`, which injects the app name and resolved `dotfiles/<subdir>` path.
- File copies use a `>>` operator on a `Path` subclass: `source >> target`. First write into a `dotfiles/<app>/` subtree deletes that subtree once per session to avoid stale files.
- OS dispatch is via `match` on a `SYSTEM` enum; unsupported combos call `log_unsupported`.
- Dependencies are vendored under `vendor/` and added to `sys.path` at import time.

### TUI (`dotfiles_tui.py`)

- Keyboard: `Tab` / `←` / `→` switches panel · `↑` / `↓` moves cursor (skips category headers) · `Space` toggles · `a` selects all · `n` clears all · `Enter` confirms · `Esc` / `Ctrl-C` cancels.
- Returns selections in menu order, left-panel picks before right-panel picks.

### Adding a new app
1. Write the backup/restore pair, decorated with `@operation`.
2. Handle each OS case explicitly; use `log_unsupported` for unsupported platforms.
3. Register the app under a category (`Terminal`, `Editor`, `Notes`, ...).

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
