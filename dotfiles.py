import functools
import os
import platform
import shutil
import sys
from enum import StrEnum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "vendor"))

from InquirerPy import inquirer
from InquirerPy.base.control import Choice
from InquirerPy.separator import Separator

# ------------------------------------------------------------------------------
# Classes
# ------------------------------------------------------------------------------
class File(Path):
    # track dotfiles dirs that we already deleted
    _deleted: set = set()

    def __rshift__(self, other) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        target = File(other)
        target._delete_dotfiles_root_once()
        if self.is_file():
            self._copy_file(target)
        else:
            self._copy_dir(target)

    def _copy_dir(self, target: Path) -> None:
        """Copy a local directory to a local target."""
        try:
            log_transfer("dir", self, target)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(self, target, dirs_exist_ok=True)
        except Exception as e:
            log_error("Failed to copy directory", e)

    def _copy_file(self, target: Path) -> None:
        """Copy a local file to a local target."""
        try:
            log_transfer("file", self, target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self, target)
        except Exception as e:
            log_error("Failed to copy file", e)

    def _delete_dotfiles_root_once(self) -> None:
        """First write into dotfiles/<app>/... deletes <app> once per session."""
        # check if inside dotfiles dir
        if not self.is_relative_to(DOTFILES):
            return

        # extract root to delete
        # jetbrains is a special case because we delete the inner tool directory, not the whole jetbrains dir
        parts = self.relative_to(DOTFILES).parts
        if parts[0] == "jetbrains":
            root = DOTFILES / parts[0] / parts[1]
        else:
            root = DOTFILES / parts[0]

        # check if already deleted
        if root in File._deleted:
            return

        # delete and track
        shutil.rmtree(root, ignore_errors=True)
        File._deleted.add(root)

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

# ------------------------------------------------------------------------------
# Decorator
# ------------------------------------------------------------------------------
def operation(app: str, dir: str):
    """Wrap a backup/restore function, injecting the app name and the resolved `dotfiles/<target_dir>` path."""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            return fn(app, DOTFILES / dir, *args, **kwargs)
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
    "options/projectView.xml",
    # "options/editor.xml",
    # "options/find.xml",
    # "options/ide.general.xml",
    # "options/keymapFlags.xml",
    # "options/laf.xml",
    # "options/terminal-font.xml",
    # "options/ui.lnf.xml",
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

@operation("JetBrains", "jetbrains")
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
    match SYSTEM:
        case OS.WIN:
            WIN_ROAMING / "Code/User/keybindings.json" >> dir / "keybindings.json"
            WIN_ROAMING / "Code/User/settings.json" >> dir / "settings.json"
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
            dir >> WIN_ROAMING / "Code/User"
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
ITEMS = {
    "Claude Code":      ("AI",       backup_claude_code,      restore_claude_code),
    "Ghostty":          ("Terminal", backup_ghostty,          restore_ghostty),
    "PowerShell":       ("Terminal", backup_powershell,       restore_powershell),
    "Starship":         ("Terminal", backup_starship,         restore_starship),
    "Warp":             ("Terminal", backup_warp,             restore_warp),
    "Windows Terminal": ("Terminal", backup_windows_terminal, restore_windows_terminal),
    "Helix":            ("Editor",   backup_helix,            restore_helix),
    "JetBrains":        ("Editor",   backup_jetbrains,        restore_jetbrains),
    "RStudio":          ("Editor",   backup_rstudio,          restore_rstudio),
    "VIM":              ("Editor",   backup_vim,              restore_vim),
    "VSCode / Cursor":  ("Editor",   backup_vscode,           restore_vscode),
    "Notable":          ("Notes",    backup_notable,          restore_notable),
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if __name__ == "__main__":

    # prepare menu
    labeled = [(name, f"{category:<8} / {name}") for name, (category, _, _) in ITEMS.items()]
    choices = [Separator("=== Backup ===")]
    choices += [Choice(("backup", name), name=label) for name, label in labeled]
    choices.append(Separator("=== Restore ==="))
    choices += [Choice(("restore", name), name=label) for name, label in labeled]

    # show menu
    selection = inquirer.checkbox(message="Select operations:", choices=choices).execute()
    if not selection:
        sys.exit(0)

    # execute operations
    for op, name in selection:
        _, backup_fn, restore_fn = ITEMS[name]
        fn = backup_fn if op == "backup" else restore_fn
        fn()
