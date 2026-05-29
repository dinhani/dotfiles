import functools
import os
import platform
import shutil
import sys
from enum import StrEnum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "vendor"))

from collections.abc import Callable

from dotfiles_tui import show_tui

# ------------------------------------------------------------------------------
# Classes
# ------------------------------------------------------------------------------
class File(Path):
    # track dotfiles dirs that we already deleted
    _deleted: set = set()
    # when False, deletes dotfiles/<app>/; when True, deletes dotfiles/<category>/<app>/ (example: JetBrains/<app>/)
    _subdir: bool = False

    def __rshift__(self, other) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        target = File(other)
        target._delete_dotfiles_root_once()
        if self.is_file():
            self._copy_file(target)
        else:
            self._copy_dir(target)

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
    match SYSTEM:
        case OS.WIN:
            dir / "settings.json" >> WIN_HOME / ".claude/settings.json"
            dir / "CLAUDE.md" >> WIN_HOME / ".claude/CLAUDE.md"
        case OS.LINUX | OS.MAC:
            dir / "settings.json" >> UNIX_HOME / ".claude/settings.json"
            dir / "CLAUDE.md" >> UNIX_HOME / ".claude/CLAUDE.md"

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
    selections = show_tui(REGISTRY_BY_CATEGORY, Op.BACKUP, Op.RESTORE)
    if not selections:
        sys.exit(0)

    for op_label, app in selections:
        op = Op(op_label)
        handler = REGISTRY_BY_APP[app][op]
        handler()
