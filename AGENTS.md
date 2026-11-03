# Project

Two independent automations for setting up and maintaining a personal/work development machine.

## Goal 1: Dotfiles backup & restore (`dotfiles.py` + `dotfiles_tui.py`)

Cross-platform (Windows / Linux / Mac) Python script that backs up app config files into the `dotfiles/` directory and restores them back to their OS-specific locations.

### Module split

- `dotfiles.py` — core/domain: file-copy primitives, OS dispatch, per-app backup/restore handlers, and the registry mapping categories → apps → handlers.
- `dotfiles_tui.py` — UI only: a generic two-panel picker built on vendored `prompt_toolkit`. Knows nothing about backup/restore — it takes panel labels as a parameter and returns `(panel_label, item_name)` selections. The TUI never imports from `dotfiles.py` (avoids a cycle).

### Core (`dotfiles.py`)

- Each app has a backup/restore pair decorated with `@operation(Op.BACKUP, ...)` / `@operation(Op.RESTORE, ...)`, which turns the function into a callable `Handler` that injects the app name and resolved `dotfiles/<subdir>` path, and registers it in `HANDLERS_BY_APP`. `CATEGORIES` lists the app names per category; an import-time check fails if an app lacks a category or either handler.
- `Comparison` holds the per-app transfers and sync results of the backup comparison and provides the TUI callbacks (`diff`, `restore_warning`, `hints`, `refresh`).
- Copy errors are logged and the run continues; the script exits with code 1 at the end if any error was logged.
- File copies use a `>>` operator on a `Path` subclass: `source >> target`. First write into a `dotfiles/<app>/` subtree deletes that subtree once per session to avoid stale files.
- OS dispatch is via `match` on a `SYSTEM` enum; unsupported combos call `log_unsupported`.
- Before the TUI opens, `Handler.collect_transfers()` runs each backup handler in compare mode (`Transfer.COMPARE`): `>>` records (machine, backup) file pairs instead of copying. `File.compare_to_backup` compares each pair by content (ignoring one trailing newline on either side); when content differs, the machine mtime is compared with `BackupHistory.get_time` (last git commit time, or mtime if uncommitted). The per-app `Sync` result is shown as a hint in the TUI.
- Dependencies are vendored under `vendor/` and added to `sys.path` at import time.

### TUI (`dotfiles_tui.py`)

- Items can be disabled per panel (shown dimmed as `[-]`, not selectable). Every row has an icon column before the checkbox; on disabled rows it shows why the item is disabled (`Disabled` with icon, color and reason), and a legend line under the help line lists the reasons in use. `dotfiles.py` disables apps whose handler is unsupported on the current OS (`✗`) and backups of apps whose `source_of_truth` OS is not the current one (the initial of the source OS, e.g. `W`).
- Keyboard: `Tab` switches panel · `←` / `→` activates the left / right panel · `↑` / `↓` / `k` / `j` moves cursor (skips category headers and disabled items) · `Home` / `End` jumps to first / last · `Space` toggles · `a` selects all · `n` clears all · `d` opens a diff popup for the cursor app (scroll with `↑` / `↓` / `k` / `j` / `PgUp` / `PgDn` / `Home` / `End`, close with `d` / `q` / `Esc`) · `Enter` runs the selection · `q` / `Esc` / `Ctrl-C` quits.
- Each item can carry a short hint, shown dimmed and right-aligned in both panels.
- Panel titles show the selected count. When any restore is selected, `dotfiles.py` asks for confirmation before running, flagging apps whose machine copy is newer.
- The diff popup shows a unified diff per differing file; on the Backup panel green is what the backup would gain, on the Restore panel green is what the machine would gain. `show_tui` takes an `item_diff(panel_label, item_name)` callback that returns the diff text.
- `Enter` runs the selected backups and restores inside the TUI (on a worker thread) through the `run` callback, with a progress popup split into three titled sections: Progress (phase, counter, bar, current item of the run), Log (live transfers, skips and errors) and Result (running, updating status, or done with the error count). `dotfiles.py` routes `log_transfer` / `log_error` / `log_unsupported` to the popup through `log_handler` while it runs. When the run ends, `refresh` runs automatically (statuses recompared, hints updated, selections cleared); the popup only shows "updating status..." in the Result section meanwhile, then the summary, and any key closes it. The TUI only exits on `q` / `Esc`.
- If any restore is selected, an in-TUI popup asks for confirmation first (`y` / `Enter` runs, `n` / `Esc` cancels), flagging apps whose machine copy is newer; the message comes from the `confirm` callback.
- Selections run in menu order, left-panel picks before right-panel picks. Exceptions raised in a callback end the TUI and are re-raised.

### Adding a new app
1. Write the backup/restore pair, decorated with `@operation(Op.BACKUP, ...)` and `@operation(Op.RESTORE, ...)`.
2. Handle each OS case explicitly; for unsupported platforms write a `case` whose only statement is `log_unsupported(app)`. `@operation` parses the handler source for exactly that shape to disable the app in the TUI on those platforms. Use that only for apps that do not exist on the OS. For apps that exist everywhere but whose backup must only be taken from one OS, pass `source_of_truth=OS.X` to the backup's `@operation`; the backup is disabled on other OSes while restore stays available, and the backup body only needs the source OS case. The source-of-truth check comes before the unsupported check, so a Windows-only app (PowerShell, Windows Terminal) shows the source icon on the Backup panel and `✗` on the Restore panel.
3. Wrap every directory path in `Dir(...)` (e.g. `Dir(dir) >> target`). On restore, `Dir` always creates the target directory, even if the backup has none; on backup, a missing source directory is skipped. Plain paths are for files.
4. Add the app name under a category in `CATEGORIES` (`Terminal`, `Editor`, `Notes`, ...).

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
