import ast
import functools
import inspect
import os
import platform
import shutil
import subprocess
import sys
from enum import Enum, StrEnum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "vendor"))

from collections.abc import Callable

from prompt_toolkit.shortcuts import confirm

from dotfiles_tui import show_tui

# ------------------------------------------------------------------------------
# Classes
# ------------------------------------------------------------------------------
class Transfer(Enum):
    COPY    = "copy"
    COMPARE = "compare"

class Sync(StrEnum):
    IN_SYNC       = "in sync"
    MACHINE_NEWER = "machine newer"
    BACKUP_NEWER  = "backup newer"
    MIXED         = "mixed"
    NO_FILES      = "no files"

    @classmethod
    def from_files(cls, files: set["Sync"]) -> "Sync":
        files_changed = files - {cls.IN_SYNC}
        if not files:
            return cls.NO_FILES
        if not files_changed:
            return cls.IN_SYNC
        if len(files_changed) > 1:
            return cls.MIXED
        return files_changed.pop()

class File(Path):
    # track dotfiles dirs that we already deleted
    _deleted: set = set()
    # when False, deletes dotfiles/<app>/; when True, deletes dotfiles/<category>/<app>/ (example: JetBrains/<app>/)
    _subdir: bool = False
    _transfer: "Transfer" = Transfer.COPY
    _compared: list[tuple["File", "File"]] = []

    def __rshift__(self, other) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        target = File(other)
        if File._transfer is Transfer.COMPARE:
            if self.is_dir() or target.is_dir():
                files = {path.relative_to(root) for root in (self, target) for path in root.rglob("*") if path.is_file()}
                File._compared.extend((self / file, target / file) for file in sorted(files))
            else:
                File._compared.append((self, target))
            return

        target._delete_dotfiles_root_once()
        if self.is_file():
            self._copy_file(target)
        else:
            self._copy_dir(target)

    def compare_to_backup(self, backup: "File", backup_times: dict[Path, float]) -> Sync | None:
        if not self.is_file() and not backup.is_file():
            return None
        if not backup.is_file():
            return Sync.MACHINE_NEWER
        if not self.is_file():
            return Sync.BACKUP_NEWER

        machine_bytes = self.read_bytes()
        if backup.read_bytes() in (machine_bytes, machine_bytes + b"\n"):
            return Sync.IN_SYNC

        if self.stat().st_mtime > backup_times.get(backup, backup.stat().st_mtime):
            return Sync.MACHINE_NEWER
        return Sync.BACKUP_NEWER

    def _copy_dir(self, target: "File") -> None:
        """Copy a local directory to a local target."""
        try:
            log_transfer("dir", self, target)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(self, target, dirs_exist_ok=True)
            if target._is_backup():
                for path in target.rglob("*"):
                    if path.is_file():
                        _ensure_trailing_newline(path)
        except Exception as e:
            log_error("Failed to copy directory", e)

    def _copy_file(self, target: "File") -> None:
        """Copy a local file to a local target."""
        try:
            log_transfer("file", self, target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self, target)
            if target._is_backup():
                _ensure_trailing_newline(target)
        except Exception as e:
            log_error("Failed to copy file", e)

    def _is_backup(self) -> bool:
        """True when this path is a backup target (inside the dotfiles dir)."""
        return self.is_relative_to(DOTFILES)

    def _delete_dotfiles_root_once(self) -> None:
        """First write into the cleanup root (dotfiles/<app>/... by default) deletes it once per session."""
        # check if inside dotfiles dir
        if not self._is_backup():
            return

        # extract root to delete; if `subdir` is set, go one level deeper than dotfiles/<app>/
        parts = self.relative_to(DOTFILES).parts
        if File._subdir:
            root = DOTFILES / parts[0] / parts[1]
        else:
            root = DOTFILES / parts[0]

        # check if already deleted
        if root in File._deleted:
            return

        # delete and track
        shutil.rmtree(root, ignore_errors=True)
        File._deleted.add(root)

def _ensure_trailing_newline(path: Path) -> None:
    """Append a newline if the file is non-empty and doesn't already end with one."""
    try:
        with open(path, "rb+") as f:
            f.seek(0, os.SEEK_END)
            if f.tell() == 0:
                return
            f.seek(-1, os.SEEK_END)
            if f.read(1) != b"\n":
                f.write(b"\n")
    except Exception as e:
        log_error("Failed to ensure trailing newline", e)

# ------------------------------------------------------------------------------
# Constants - Directories
# ------------------------------------------------------------------------------
DOTFILES: File = File(Path(__file__).parent / "dotfiles")
"""Path of local dotfiles directory (relative to this script)."""

UNIX_HOME: File = File(Path.home())
"""Path of Unix home directory (Linux and Mac)."""

WIN_HOME: File = File(os.environ.get("USERPROFILE", ""))
"""Path of Windows home directory."""

WIN_ROAMING: File = WIN_HOME / "AppData" / "Roaming"
"""Path of Windows AppData/Roaming directory."""

WIN_LOCAL: File = WIN_HOME / "AppData" / "Local"
"""Path of Windows AppData/Local directory."""

WIN_SCOOP: File = File(os.environ.get("SCOOP") or WIN_HOME / "scoop")
"""Path of Windows Scoop directory; portable apps keep their data under `persist/<app>/`."""

MAC_APP_SUPPORT: File = File(Path.home() / "Library" / "Application Support")
"""Path of Mac Application Support directory."""

# ------------------------------------------------------------------------------
# Functions - Log
# ------------------------------------------------------------------------------
COLOR_RESET  = "\033[0m"
COLOR_RED    = "\033[91m"
COLOR_GREEN  = "\033[92m"
COLOR_YELLOW = "\033[93m"
COLOR_CYAN   = "\033[96m"

def log_transfer(kind: str, source: Path, target: Path) -> None:
    print("")
    print(f"{COLOR_GREEN}{kind:<4}{COLOR_RESET}  {source} {COLOR_CYAN}→{COLOR_RESET} {target}")

def log_error(message: str, exception: Exception) -> None:
    print("")
    print(f"{COLOR_RED}err {COLOR_RESET}  {message}: {exception}")

def log_unsupported(item: str) -> None:
    print("")
    print(f"{COLOR_YELLOW}skip{COLOR_RESET}  {item}: unsupported on {SYSTEM}")

# ------------------------------------------------------------------------------
# Platform
# ------------------------------------------------------------------------------
class OS(StrEnum):
    WIN   = "Windows"
    MAC   = "Darwin"
    LINUX = "Linux"

SYSTEM = OS(platform.system())

class Op(StrEnum):
    BACKUP  = "Backup"
    RESTORE = "Restore"

# ------------------------------------------------------------------------------
# Decorator
# ------------------------------------------------------------------------------
def operation(app: str, dir: str, subdir: bool = False):
    """Wrap a backup/restore function, injecting the app name and the resolved `dotfiles/<target_dir>` path.

    Set `subdir=True` for apps whose backup lives one level deeper (e.g. JetBrains, where each tool has
    its own subdir under `dotfiles/jetbrains/` that must be preserved when the tool isn't installed on
    the current machine).
    """
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            File._subdir = subdir
            try:
                return fn(app, DOTFILES / dir, *args, **kwargs)
            finally:
                File._subdir = False

        systems_unsupported: set[OS] = set()
        for node in ast.walk(ast.parse(inspect.getsource(fn))):
            match node:
                case ast.match_case(pattern, body=[ast.Expr(ast.Call(ast.Name(name)))]) if name == log_unsupported.__name__:
                    systems_unsupported |= {OS[value.attr] for value in ast.walk(pattern) if isinstance(value, ast.Attribute)}
        wrapper.systems_unsupported = systems_unsupported

        return wrapper
    return decorator

# ------------------------------------------------------------------------------
# Items - Claude Code
# ------------------------------------------------------------------------------
@operation("Claude Code", "claude-code")
def backup_claude_code(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_HOME / ".claude/settings.json" >> dir / "settings.json"
            WIN_HOME / ".claude/CLAUDE.md" >> dir / "CLAUDE.md"
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".claude/settings.json" >> dir / "settings.json"
            UNIX_HOME / ".claude/CLAUDE.md" >> dir / "CLAUDE.md"

@operation("Claude Code", "claude-code")
def restore_claude_code(app: str, dir: File):
    def write_cursor_rule(target: File) -> None:
        source = dir / "CLAUDE.md"
        try:
            log_transfer("file", source, target)
            target.parent.mkdir(parents=True, exist_ok=True)
            frontmatter = "---\ndescription: Global programming rules\nalwaysApply: true\n---\n"
            target.write_text(frontmatter + source.read_text(encoding="utf-8"), encoding="utf-8")
        except Exception as e:
            log_error("Failed to write Cursor rule", e)

    match SYSTEM:
        case OS.WIN:
            dir / "settings.json" >> WIN_HOME / ".claude/settings.json"
            dir / "CLAUDE.md" >> WIN_HOME / ".claude/CLAUDE.md"
            dir / "CLAUDE.md" >> WIN_HOME / ".codex/AGENTS.md"
            write_cursor_rule(WIN_HOME / ".cursor/rules/global-rules.mdc")
            if (WIN_HOME / ".claude-2").is_dir():
                dir / "settings.json" >> WIN_HOME / ".claude-2/settings.json"
                dir / "CLAUDE.md" >> WIN_HOME / ".claude-2/CLAUDE.md"
        case OS.LINUX | OS.MAC:
            dir / "settings.json" >> UNIX_HOME / ".claude/settings.json"
            dir / "CLAUDE.md" >> UNIX_HOME / ".claude/CLAUDE.md"
            dir / "CLAUDE.md" >> UNIX_HOME / ".codex/AGENTS.md"
            write_cursor_rule(UNIX_HOME / ".cursor/rules/global-rules.mdc")
            if (UNIX_HOME / ".claude-2").is_dir():
                dir / "settings.json" >> UNIX_HOME / ".claude-2/settings.json"
                dir / "CLAUDE.md" >> UNIX_HOME / ".claude-2/CLAUDE.md"

# ------------------------------------------------------------------------------
# Items - Ghostty
# ------------------------------------------------------------------------------
@operation("Ghostty", "ghostty")
def backup_ghostty(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/ghostty/config" >> dir / "config"

@operation("Ghostty", "ghostty")
def restore_ghostty(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".config/ghostty"

# ------------------------------------------------------------------------------
# Items - Helix
# ------------------------------------------------------------------------------
@operation("Helix", "helix")
def backup_helix(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_ROAMING / "helix/config.toml" >> dir / "config.toml"
            WIN_ROAMING / "helix/languages.toml" >> dir / "languages.toml"
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/helix/config.toml" >> dir / "config.toml"
            UNIX_HOME / ".config/helix/languages.toml" >> dir / "languages.toml"

@operation("Helix", "helix")
def restore_helix(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_ROAMING / "helix"
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".config/helix"

# ------------------------------------------------------------------------------
# Items - JetBrains
# ------------------------------------------------------------------------------
JETBRAINS_TOOLS = (
    "CLion",
    "DataGrip",
    "DataSpell",
    "GoLand",
    "IntelliJIdea",
    "PhpStorm",
    "PyCharm",
    "Rider",
    "RubyMine",
    "RustRover",
    "WebStorm",
)

JETBRAINS_FILES = (
    "keymaps",
    "options/advancedSettings.xml",
    "options/colors.scheme.xml",
    "options/editor-font.xml",
    "options/ide.general.xml",
    "options/laf.xml",
    "options/projectView.xml",
    "options/ui.lnf.xml",
    # "options/editor.xml",
    # "options/find.xml",
    # "options/keymapFlags.xml",
    # "options/terminal-font.xml",
    # "options/window.layouts.xml",
)

def jetbrains_installs() -> dict[str, File]:
    """Latest install folder for each installed JetBrains tool."""
    match SYSTEM:
        case OS.WIN:
            root = WIN_ROAMING / "JetBrains"
        case OS.MAC:
            root = MAC_APP_SUPPORT / "JetBrains"
        case OS.LINUX:
            root = UNIX_HOME / ".config/JetBrains"
    installs: dict[str, File] = {}
    for tool in JETBRAINS_TOOLS:
        versions = sorted(root.glob(f"{tool}[0-9]*"))
        if versions:
            installs[tool] = File(versions[-1])
    return installs

@operation("JetBrains", "jetbrains", subdir=True)
def backup_jetbrains(app: str, dir: File):
    for tool, install in jetbrains_installs().items():
        for file in JETBRAINS_FILES:
            source = install / file
            if not source.exists():
                continue
            source >> dir / tool / file

@operation("JetBrains", "jetbrains")
def restore_jetbrains(app: str, dir: File):
    for tool, install in jetbrains_installs().items():
        for file in JETBRAINS_FILES:
            source = dir / tool / file
            if not source.exists():
                continue
            source >> install / file

# ------------------------------------------------------------------------------
# Items - Notable
# ------------------------------------------------------------------------------
@operation("Notable", "notable")
def backup_notable(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_HOME / ".notable.json" >> dir / ".notable.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("Notable", "notable")
def restore_notable(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir / ".notable.json" >> WIN_HOME / ".notable.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - PowerShell
# ------------------------------------------------------------------------------
@operation("PowerShell", "powershell")
def backup_powershell(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_HOME / "Documents/PowerShell/Microsoft.PowerShell_profile.ps1" >> dir / "Microsoft.PowerShell_profile.ps1"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("PowerShell", "powershell")
def restore_powershell(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir / "Microsoft.PowerShell_profile.ps1" >> WIN_HOME / "Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - RStudio
# ------------------------------------------------------------------------------
@operation("RStudio", "rstudio")
def backup_rstudio(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_ROAMING / "RStudio/config.json" >> dir / "config.json"
            WIN_ROAMING / "RStudio/keybindings" >> dir / "keybindings"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("RStudio", "rstudio")
def restore_rstudio(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_ROAMING / "RStudio"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - Starship
# ------------------------------------------------------------------------------
@operation("Starship", "starship")
def backup_starship(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".config/starship.toml" >> dir / "starship.toml"

@operation("Starship", "starship")
def restore_starship(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir / "starship.toml" >> UNIX_HOME / ".config/starship.toml"

# ------------------------------------------------------------------------------
# Items - VIM
# ------------------------------------------------------------------------------
@operation("VIM", "vim")
def backup_vim(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".vimrc" >> dir / ".vimrc"

@operation("VIM", "vim")
def restore_vim(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir / ".vimrc" >> UNIX_HOME / ".vimrc"

# ------------------------------------------------------------------------------
# Items - VSCode / Cursor
# ------------------------------------------------------------------------------
@operation("VSCode / Cursor", "vscode")
def backup_vscode(app: str, dir: File):
    # Scoop installs VSCode as a portable app, so its config lives under persist/ instead of %AppData%\Code.
    match SYSTEM:
        case OS.WIN:
            WIN_SCOOP / "persist/vscode/data/user-data/User/keybindings.json" >> dir / "keybindings.json"
            WIN_SCOOP / "persist/vscode/data/user-data/User/settings.json" >> dir / "settings.json"
        case OS.LINUX:
            UNIX_HOME / ".config/Code/User/keybindings.json" >> dir / "keybindings.json"
            UNIX_HOME / ".config/Code/User/settings.json" >> dir / "settings.json"
        case OS.MAC:
            MAC_APP_SUPPORT / "Code/User/keybindings.json" >> dir / "keybindings.json"
            MAC_APP_SUPPORT / "Code/User/settings.json" >> dir / "settings.json"

@operation("VSCode / Cursor", "vscode")
def restore_vscode(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_SCOOP / "persist/vscode/data/user-data/User"
            dir >> WIN_ROAMING / "Cursor/User"
        case OS.LINUX:
            dir >> UNIX_HOME / ".config/Code/User"
            dir >> UNIX_HOME / ".config/Cursor/User"
        case OS.MAC:
            dir >> MAC_APP_SUPPORT / "Code/User"
            dir >> MAC_APP_SUPPORT / "Cursor/User"

# ------------------------------------------------------------------------------
# Items - Warp
# ------------------------------------------------------------------------------
@operation("Warp", "warp")
def backup_warp(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            UNIX_HOME / ".warp/keybindings.yaml" >> dir / "keybindings.yaml"
            UNIX_HOME / ".warp/settings.toml" >> dir / "settings.toml"

@operation("Warp", "warp")
def restore_warp(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dir >> UNIX_HOME / ".warp"

# ------------------------------------------------------------------------------
# Items - Windows Terminal
# ------------------------------------------------------------------------------
@operation("Windows Terminal", "windows-terminal")
def backup_windows_terminal(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            WIN_LOCAL / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" >> dir / "settings.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("Windows Terminal", "windows-terminal")
def restore_windows_terminal(app: str, dir: File):
    match SYSTEM:
        case OS.WIN:
            dir >> WIN_LOCAL / "Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Registry
# ------------------------------------------------------------------------------
REGISTRY_BY_CATEGORY: dict[str, dict[str, dict[Op, Callable[[], None]]]] = {
    "AI": {
        "Claude Code": {Op.BACKUP: backup_claude_code, Op.RESTORE: restore_claude_code},
    },
    "Terminal": {
        "Ghostty":          {Op.BACKUP: backup_ghostty,          Op.RESTORE: restore_ghostty},
        "PowerShell":       {Op.BACKUP: backup_powershell,       Op.RESTORE: restore_powershell},
        "Starship":         {Op.BACKUP: backup_starship,         Op.RESTORE: restore_starship},
        "Warp":             {Op.BACKUP: backup_warp,             Op.RESTORE: restore_warp},
        "Windows Terminal": {Op.BACKUP: backup_windows_terminal, Op.RESTORE: restore_windows_terminal},
    },
    "Editor": {
        "Helix":           {Op.BACKUP: backup_helix,     Op.RESTORE: restore_helix},
        "JetBrains":       {Op.BACKUP: backup_jetbrains, Op.RESTORE: restore_jetbrains},
        "RStudio":         {Op.BACKUP: backup_rstudio,   Op.RESTORE: restore_rstudio},
        "VIM":             {Op.BACKUP: backup_vim,       Op.RESTORE: restore_vim},
        "VSCode / Cursor": {Op.BACKUP: backup_vscode,    Op.RESTORE: restore_vscode},
    },
    "Notes": {
        "Notable": {Op.BACKUP: backup_notable, Op.RESTORE: restore_notable},
    },
}

REGISTRY_BY_APP: dict[str, dict[Op, Callable[[], None]]] = {
    app: handlers
    for category in REGISTRY_BY_CATEGORY.values()
    for app, handlers in category.items()
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    repo = DOTFILES.parent
    git = ["git", "-c", "core.quotePath=false"]
    git_log = subprocess.run([*git, "log", "--format=@%ct", "--name-only", "--", DOTFILES.name], cwd=repo, capture_output=True, encoding="utf-8", check=True).stdout
    git_status = subprocess.run([*git, "status", "--porcelain", "--untracked-files=all", "--", DOTFILES.name], cwd=repo, capture_output=True, encoding="utf-8", check=True).stdout

    backup_times: dict[Path, float] = {}
    commit_time = 0.0
    for line in git_log.splitlines():
        if line.startswith("@"):
            commit_time = float(line[1:])
        elif line:
            backup_times.setdefault(repo / line, commit_time)
    for line in git_status.splitlines():
        backup_times.pop(repo / line[3:].split(" -> ")[-1], None)

    items_hint: dict[str, str] = {}
    File._transfer = Transfer.COMPARE
    for app, handlers in REGISTRY_BY_APP.items():
        handler = handlers[Op.BACKUP]
        if SYSTEM in handler.systems_unsupported:
            continue
        File._compared.clear()
        handler()
        files = {machine.compare_to_backup(backup, backup_times) for machine, backup in File._compared}
        items_hint[app] = Sync.from_files(files - {None})
    File._transfer = Transfer.COPY

    selections = show_tui(
        items={category: list(apps) for category, apps in REGISTRY_BY_CATEGORY.items()},
        items_disabled={
            op: {app for app, handlers in REGISTRY_BY_APP.items() if SYSTEM in handlers[op].systems_unsupported}
            for op in Op
        },
        items_hint=items_hint,
        panel_left=Op.BACKUP,
        panel_right=Op.RESTORE,
    )
    if not selections:
        sys.exit(0)

    apps_restore = [app for op_label, app in selections if op_label == Op.RESTORE]
    if apps_restore and not confirm(f"Restore overwrites local config for: {', '.join(apps_restore)}. Continue?"):
        sys.exit(0)

    for op_label, app in selections:
        op = Op(op_label)
        handler = REGISTRY_BY_APP[app][op]
        handler()
