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
    def __rshift__(self, other) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        target = Path(other)
        if self.is_file():
            self.cp_file(target)
        else:
            self.cp_dir(target)

    def cp_dir(self, target: Path) -> None:
        """Copy a local directory to a local target."""
        try:
            log_transfer("Dir", "Dir", self, target)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(self, target, dirs_exist_ok=True)
        except Exception as e:
            log_error("Failed to copy directory", e)

    def cp_file(self, target: Path) -> None:
        """Copy a local file to a local target."""
        try:
            log_transfer("File", "File", self, target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self, target)
        except Exception as e:
            log_error("Failed to copy file", e)

# ------------------------------------------------------------------------------
# Functions - Log
# ------------------------------------------------------------------------------
def log_transfer(kind_source: str, kind_target: str, source: Path, target: Path) -> None:
    """Log a transfer operation."""
    print()
    print(f"{kind_source} -> {kind_target}")
    print(f"  {source} -> {target}")

def log_error(message: str, exception: Exception) -> None:
    """Log an error message."""
    print(f"  [!] {message}: {exception}")

def log_unsupported(item: str) -> None:
    """Log that an item is not supported on the current platform."""
    print()
    print(f"[skip] {item}: unsupported on {CURRENT_OS}")

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
    return File("dotfiles", path)

# ------------------------------------------------------------------------------
# Items - Ghostty
# ------------------------------------------------------------------------------
def backup_ghostty():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("Ghostty")
        case OS.MAC | OS.LINUX:
            unix_home(".config/ghostty/config") >> dotfiles("ghostty/config")

def restore_ghostty():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("Ghostty")
        case OS.MAC | OS.LINUX:
            dotfiles("ghostty") >> unix_home(".config/ghostty")

# ------------------------------------------------------------------------------
# Items - Helix
# ------------------------------------------------------------------------------
def backup_helix():
    match CURRENT_OS:
        case OS.WIN:
            unix_home(".config/helix/config.toml") >> dotfiles("helix/config.toml")
            unix_home(".config/helix/languages.toml") >> dotfiles("helix/languages.toml")
        case OS.MAC | OS.LINUX:
            unix_home(".config/helix/config.toml") >> dotfiles("helix/config.toml")
            unix_home(".config/helix/languages.toml") >> dotfiles("helix/languages.toml")

def restore_helix():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("helix") >> unix_home(".config/helix")
            dotfiles("helix") >> win_roaming("helix")
        case OS.MAC | OS.LINUX:
            dotfiles("helix") >> unix_home(".config/helix")

# ------------------------------------------------------------------------------
# Items - IntelliJ
# ------------------------------------------------------------------------------
def backup_intellij():
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("JetBrains/IntelliJIdea2025.3/keymaps") >> dotfiles("intellij/keymaps")
            win_roaming("JetBrains/IntelliJIdea2025.3/options/editor.xml") >> dotfiles("intellij/options/editor.xml")
            win_roaming("JetBrains/IntelliJIdea2025.3/options/editor-font.xml") >> dotfiles("intellij/options/editor-font.xml")
            win_roaming("JetBrains/IntelliJIdea2025.3/options/window.layouts.xml") >> dotfiles("intellij/options/window.layouts.xml")
        case OS.MAC | OS.LINUX:
            log_unsupported("IntelliJ")

def restore_intellij():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("intellij") >> win_roaming("JetBrains/IntelliJIdea2025.3")
        case OS.MAC:
            dotfiles("intellij") >> mac_app_support("JetBrains/IntelliJIdea2025.3")
        case OS.LINUX:
            log_unsupported("IntelliJ")

# ------------------------------------------------------------------------------
# Items - Notable
# ------------------------------------------------------------------------------
def backup_notable():
    match CURRENT_OS:
        case OS.WIN:
            win_home(".notable.json") >> dotfiles("notable/.notable.json")
        case OS.MAC | OS.LINUX:
            log_unsupported("Notable")

def restore_notable():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("notable/.notable.json") >> win_home(".notable.json")
        case OS.MAC | OS.LINUX:
            log_unsupported("Notable")

# ------------------------------------------------------------------------------
# Items - PowerShell
# ------------------------------------------------------------------------------
def backup_powershell():
    match CURRENT_OS:
        case OS.WIN:
            win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1") >> dotfiles("powershell/Microsoft.PowerShell_profile.ps1")
        case OS.MAC | OS.LINUX:
            log_unsupported("PowerShell")

def restore_powershell():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("powershell/Microsoft.PowerShell_profile.ps1") >> win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")
        case OS.MAC | OS.LINUX:
            log_unsupported("PowerShell")

# ------------------------------------------------------------------------------
# Items - RStudio
# ------------------------------------------------------------------------------
def backup_rstudio():
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("RStudio/config.json") >> dotfiles("rstudio/config.json")
            win_roaming("RStudio/keybindings") >> dotfiles("rstudio/keybindings")
        case OS.MAC | OS.LINUX:
            log_unsupported("RStudio")

def restore_rstudio():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("rstudio") >> win_roaming("RStudio")
        case OS.MAC | OS.LINUX:
            log_unsupported("RStudio")

# ------------------------------------------------------------------------------
# Items - Starship
# ------------------------------------------------------------------------------
def backup_starship():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("Starship")
        case OS.MAC | OS.LINUX:
            unix_home(".config/starship.toml") >> dotfiles("starship/starship.toml")

def restore_starship():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("Starship")
        case OS.MAC | OS.LINUX:
            dotfiles("starship/starship.toml") >> unix_home(".config/starship.toml")

# ------------------------------------------------------------------------------
# Items - VIM
# ------------------------------------------------------------------------------
def backup_vim():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("VIM")
        case OS.MAC | OS.LINUX:
            unix_home(".vimrc") >> dotfiles("vim/.vimrc")

def restore_vim():
    match CURRENT_OS:
        case OS.WIN:
            log_unsupported("VIM")
        case OS.MAC | OS.LINUX:
            dotfiles("vim/.vimrc") >> unix_home(".vimrc")

# ------------------------------------------------------------------------------
# Items - VSCode / Cursor
# ------------------------------------------------------------------------------
def backup_vscode():
    match CURRENT_OS:
        case OS.WIN:
            win_roaming("Code/User/keybindings.json") >> dotfiles("vscode/keybindings.json")
            win_roaming("Code/User/settings.json") >> dotfiles("vscode/settings.json")
        case OS.MAC | OS.LINUX:
            log_unsupported("VSCode / Cursor")

def restore_vscode():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("vscode") >> win_roaming("Code/User")
            dotfiles("vscode") >> win_roaming("Cursor/User")
        case OS.MAC:
            dotfiles("vscode") >> mac_app_support("Code/User")
            dotfiles("vscode") >> mac_app_support("Cursor/User")
        case OS.LINUX:
            log_unsupported("VSCode / Cursor")

# ------------------------------------------------------------------------------
# Items - Windows Terminal
# ------------------------------------------------------------------------------
def backup_windows_terminal():
    match CURRENT_OS:
        case OS.WIN:
            win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json") >> dotfiles("windows-terminal/settings.json")
        case OS.MAC | OS.LINUX:
            log_unsupported("Windows Terminal")

def restore_windows_terminal():
    match CURRENT_OS:
        case OS.WIN:
            dotfiles("windows-terminal") >> win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/")
        case OS.MAC | OS.LINUX:
            log_unsupported("Windows Terminal")

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
    selected = inquirer.checkbox(message="Select operations:", choices=choices).execute()
    if not selected:
        sys.exit(0)

    # execute operations
    for operation, name in selected:
        _, backup_fn, restore_fn = ITEMS[name]
        fn = backup_fn if operation == "backup" else restore_fn
        fn()
