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
DIR_DOTFILES = Path(__file__).parent / "dotfiles"

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
        if not self.is_relative_to(DIR_DOTFILES):
            return

        # check if already deleted
        root = DIR_DOTFILES / self.relative_to(DIR_DOTFILES).parts[0]
        if root in File._deleted:
            return

        # delete and track
        shutil.rmtree(root, ignore_errors=True)
        File._deleted.add(root)

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
    print(f"{COLOR_YELLOW}skip{COLOR_RESET}  {item}: unsupported on {CURRENT_OS}")

# ------------------------------------------------------------------------------
# Platform
# ------------------------------------------------------------------------------
class OS(StrEnum):
    WIN   = "Windows"
    MAC   = "Darwin"
    LINUX = "Linux"

CURRENT_OS = OS(platform.system())

# ------------------------------------------------------------------------------
# Functions - Directories
# ------------------------------------------------------------------------------
def unix_home(path: str = "") -> File:
    """Path of Unix home directory (Linux and Mac)."""
    return File(Path.home(), path)

def win_home(path: str = "") -> File:
    """Path of Windows home directory."""
    return File(os.environ["USERPROFILE"], path)

def win_root(path: str = "") -> File:
    """Path of Windows root directory."""
    return File("C:/", path)

def win_docs(path: str = "") -> File:
    """Path of Windows Documents directory."""
    return win_home(f"Documents/{path}")

def win_roaming(path: str = "") -> File:
    """Path of Windows AppData/Roaming directory."""
    return win_home(f"AppData/Roaming/{path}")

def win_local(path: str = "") -> File:
    """Path of Windows AppData/Local directory."""
    return win_home(f"AppData/Local/{path}")

def win_prog32(path: str = "") -> File:
    """Path of Windows Program Files (x86) directory."""
    return File("C:/Program Files (x86)", path)

def win_prog64(path: str = "") -> File:
    """Path of Windows Program Files (x64) directory."""
    return File("C:/Program Files", path)

def mac_app_support(path: str = "") -> File:
    """Path of Mac Application Support directory."""
    return File(Path.home(), "Library/Application Support", path)

def dotfiles(path: str = "") -> File:
    """Path of dotfiles backup directory."""
    return File(DIR_DOTFILES, path)

# ------------------------------------------------------------------------------
# Decorator
# ------------------------------------------------------------------------------
def operation(app, target_dir: str):
    """Wrap a backup/restore function, injecting the app name and the resolved `dotfiles/<target_dir>` path."""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            dotfiles_dir = dotfiles(target_dir)
            return fn(app, dotfiles_dir, *args, **kwargs)
        return wrapper
    return decorator

# ------------------------------------------------------------------------------
# Items - Ghostty
# ------------------------------------------------------------------------------
@operation("Ghostty", "ghostty")
def backup_ghostty(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            unix_home(".config/ghostty/config") >> dotfiles_dir / "config"

@operation("Ghostty", "ghostty")
def restore_ghostty(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dotfiles_dir >> unix_home(".config/ghostty")

# ------------------------------------------------------------------------------
# Items - Helix
# ------------------------------------------------------------------------------
@operation("Helix", "helix")
def backup_helix(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("helix/config.toml") >> dotfiles_dir / "config.toml"
            win_roaming("helix/languages.toml") >> dotfiles_dir / "languages.toml"
        case OS.LINUX | OS.MAC:
            unix_home(".config/helix/config.toml") >> dotfiles_dir / "config.toml"
            unix_home(".config/helix/languages.toml") >> dotfiles_dir / "languages.toml"

@operation("Helix", "helix")
def restore_helix(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir >> win_roaming("helix")
        case OS.LINUX | OS.MAC:
            dotfiles_dir >> unix_home(".config/helix")

# ------------------------------------------------------------------------------
# Items - IntelliJ
# ------------------------------------------------------------------------------
@operation("IntelliJ", "intellij")
def backup_intellij(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("JetBrains/IntelliJIdea2025.3/keymaps") >> dotfiles_dir / "keymaps"
            win_roaming("JetBrains/IntelliJIdea2025.3/options/editor.xml") >> dotfiles_dir / "options/editor.xml"
            win_roaming("JetBrains/IntelliJIdea2025.3/options/editor-font.xml") >> dotfiles_dir / "options/editor-font.xml"
            win_roaming("JetBrains/IntelliJIdea2025.3/options/window.layouts.xml") >> dotfiles_dir / "options/window.layouts.xml"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("IntelliJ", "intellij")
def restore_intellij(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir >> win_roaming("JetBrains/IntelliJIdea2025.3")
        case OS.LINUX:
            log_unsupported(app)
        case OS.MAC:
            dotfiles_dir >> mac_app_support("JetBrains/IntelliJIdea2025.3")

# ------------------------------------------------------------------------------
# Items - Notable
# ------------------------------------------------------------------------------
@operation("Notable", "notable")
def backup_notable(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_home(".notable.json") >> dotfiles_dir / ".notable.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("Notable", "notable")
def restore_notable(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir / ".notable.json" >> win_home(".notable.json")
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - PowerShell
# ------------------------------------------------------------------------------
@operation("PowerShell", "powershell")
def backup_powershell(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1") >> dotfiles_dir / "Microsoft.PowerShell_profile.ps1"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("PowerShell", "powershell")
def restore_powershell(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir / "Microsoft.PowerShell_profile.ps1" >> win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - RStudio
# ------------------------------------------------------------------------------
@operation("RStudio", "rstudio")
def backup_rstudio(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("RStudio/config.json") >> dotfiles_dir / "config.json"
            win_roaming("RStudio/keybindings") >> dotfiles_dir / "keybindings"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("RStudio", "rstudio")
def restore_rstudio(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir >> win_roaming("RStudio")
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Items - Starship
# ------------------------------------------------------------------------------
@operation("Starship", "starship")
def backup_starship(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            unix_home(".config/starship.toml") >> dotfiles_dir / "starship.toml"

@operation("Starship", "starship")
def restore_starship(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dotfiles_dir / "starship.toml" >> unix_home(".config/starship.toml")

# ------------------------------------------------------------------------------
# Items - VIM
# ------------------------------------------------------------------------------
@operation("VIM", "vim")
def backup_vim(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            unix_home(".vimrc") >> dotfiles_dir / ".vimrc"

@operation("VIM", "vim")
def restore_vim(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported(app)
        case OS.LINUX | OS.MAC:
            dotfiles_dir / ".vimrc" >> unix_home(".vimrc")

# ------------------------------------------------------------------------------
# Items - VSCode / Cursor
# ------------------------------------------------------------------------------
@operation("VSCode / Cursor", "vscode")
def backup_vscode(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("Code/User/keybindings.json") >> dotfiles_dir / "keybindings.json"
            win_roaming("Code/User/settings.json") >> dotfiles_dir / "settings.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("VSCode / Cursor", "vscode")
def restore_vscode(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir >> win_roaming("Code/User")
            dotfiles_dir >> win_roaming("Cursor/User")
        case OS.LINUX:
            log_unsupported(app)
        case OS.MAC:
            dotfiles_dir >> mac_app_support("Code/User")
            dotfiles_dir >> mac_app_support("Cursor/User")

# ------------------------------------------------------------------------------
# Items - Windows Terminal
# ------------------------------------------------------------------------------
@operation("Windows Terminal", "windows-terminal")
def backup_windows_terminal(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json") >> dotfiles_dir / "settings.json"
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

@operation("Windows Terminal", "windows-terminal")
def restore_windows_terminal(app, dotfiles_dir: File):
    match CURRENT_OS:
        case OS.WIN:
            dotfiles_dir >> win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState")
        case OS.LINUX | OS.MAC:
            log_unsupported(app)

# ------------------------------------------------------------------------------
# Registry
# ------------------------------------------------------------------------------
ITEMS = {
    "Ghostty":          ("Terminal", backup_ghostty,          restore_ghostty),
    "PowerShell":       ("Terminal", backup_powershell,       restore_powershell),
    "Starship":         ("Terminal", backup_starship,         restore_starship),
    "Windows Terminal": ("Terminal", backup_windows_terminal, restore_windows_terminal),
    "Helix":            ("Editor",   backup_helix,            restore_helix),
    "IntelliJ":         ("Editor",   backup_intellij,         restore_intellij),
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
