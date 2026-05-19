import os
import platform
import shutil
import sys
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
            self.log_transfer("Dir", "Dir", target)
            target.mkdir(parents=True, exist_ok=True)
            shutil.copytree(self, target, dirs_exist_ok=True)
        except Exception as e:
            self.log_error("Failed to copy directory", e)

    def cp_file(self, target: Path) -> None:
        """Copy a local file to a local target."""
        try:
            self.log_transfer("File", "File", target)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(self, target)
        except Exception as e:
            self.log_error("Failed to copy file", e)

    def log_transfer(self, kind_source, kind_target, target) -> None:
        """Log a transfer operation."""
        print()
        print(f"{kind_source} -> {kind_target}")
        print(f"  {self} -> {target}")

    @staticmethod
    def log_error(message, exception) -> None:
        """Log an error message."""
        print(f"  [!] {message}: {exception}")

# ------------------------------------------------------------------------------
# Functions - OS/Directories
# ------------------------------------------------------------------------------
def is_linux() -> bool:
    """Check if current system is Linux (includes WSL)."""
    return platform.system() == "Linux"

def is_mac() -> bool:
    """Check if current system is MacOs."""
    return platform.system() == "Darwin"

def is_win() -> bool:
    """Check if current system is Windows."""
    return platform.system() == "Windows"

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
# Items - Flydigi
# ------------------------------------------------------------------------------
def backup_flydigi():
    if is_win():
        win_prog64("FlydigiSpaceStation/config/share/") >> dotfiles("flydigi/share")

def restore_flydigi():
    if is_win():
        dotfiles("flydigi") >> win_prog64("FlydigiSpaceStation/config")

# ------------------------------------------------------------------------------
# Items - Ghostty
# ------------------------------------------------------------------------------
def backup_ghostty():
    unix_home(".config/ghostty/config") >> dotfiles("ghostty/config")

def restore_ghostty():
    dotfiles("ghostty") >> unix_home(".config/ghostty")

# ------------------------------------------------------------------------------
# Items - Helix
# ------------------------------------------------------------------------------
def backup_helix():
    unix_home(".config/helix/config.toml") >> dotfiles("helix/config.toml")
    unix_home(".config/helix/languages.toml") >> dotfiles("helix/languages.toml")

def restore_helix():
    dotfiles("helix") >> unix_home(".config/helix")
    if is_win():
        dotfiles("helix") >> win_roaming("helix")

# ------------------------------------------------------------------------------
# Items - IntelliJ
# ------------------------------------------------------------------------------
def backup_intellij():
    if is_win():
        win_roaming("JetBrains/IntelliJIdea2025.3/keymaps") >> dotfiles("intellij/keymaps")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/editor.xml") >> dotfiles("intellij/options/editor.xml")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/editor-font.xml") >> dotfiles("intellij/options/editor-font.xml")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/window.layouts.xml") >> dotfiles("intellij/options/window.layouts.xml")

def restore_intellij():
    if is_win():
        dotfiles("intellij") >> win_roaming("JetBrains/IntelliJIdea2025.3")
    if is_mac():
        dotfiles("intellij") >> mac_app_support("JetBrains/IntelliJIdea2025.3")

# ------------------------------------------------------------------------------
# Items - Notable
# ------------------------------------------------------------------------------
def backup_notable():
    if is_win():
        win_home(".notable.json") >> dotfiles("notable/.notable.json")

def restore_notable():
    if is_win():
        dotfiles("notable/.notable.json") >> win_home(".notable.json")

# ------------------------------------------------------------------------------
# Items - PowerShell
# ------------------------------------------------------------------------------
def backup_powershell():
    if is_win():
        win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1") >> dotfiles("powershell/Microsoft.PowerShell_profile.ps1")

def restore_powershell():
    if is_win():
        dotfiles("powershell/Microsoft.PowerShell_profile.ps1") >> win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")

# ------------------------------------------------------------------------------
# Items - RStudio
# ------------------------------------------------------------------------------
def backup_rstudio():
    if is_win():
        win_roaming("RStudio/config.json") >> dotfiles("rstudio/config.json")
        win_roaming("RStudio/keybindings") >> dotfiles("rstudio/keybindings")

def restore_rstudio():
    if is_win():
        dotfiles("rstudio") >> win_roaming("RStudio")

# ------------------------------------------------------------------------------
# Items - Starship
# ------------------------------------------------------------------------------
def backup_starship():
    unix_home(".config/starship.toml") >> dotfiles("starship/starship.toml")

def restore_starship():
    dotfiles("starship/starship.toml") >> unix_home(".config/starship.toml")

# ------------------------------------------------------------------------------
# Items - VIM
# ------------------------------------------------------------------------------
def backup_vim():
    unix_home(".vimrc") >> dotfiles("vim/.vimrc")

def restore_vim():
    dotfiles("vim/.vimrc") >> unix_home(".vimrc")

# ------------------------------------------------------------------------------
# Items - VSCode / Cursor
# ------------------------------------------------------------------------------
def backup_vscode():
    if is_win():
        win_roaming("Code/User/keybindings.json") >> dotfiles("vscode/keybindings.json")
        win_roaming("Code/User/settings.json") >> dotfiles("vscode/settings.json")

def restore_vscode():
    if is_win():
        dotfiles("vscode") >> win_roaming("Code/User")
        dotfiles("vscode") >> win_roaming("Cursor/User")
    if is_mac():
        dotfiles("vscode") >> mac_app_support("Code/User")
        dotfiles("vscode") >> mac_app_support("Cursor/User")

# ------------------------------------------------------------------------------
# Items - Windows Terminal
# ------------------------------------------------------------------------------
def backup_windows_terminal():
    if is_win():
        win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json") >> dotfiles("windows-terminal/settings.json")

def restore_windows_terminal():
    if is_win():
        dotfiles("windows-terminal") >> win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/")

# ------------------------------------------------------------------------------
# Registry
# ------------------------------------------------------------------------------
CATEGORY_ORDER = ["Terminal", "Editor", "Notes", "Device"]

ITEMS = {
    "Flydigi":          ("Device",   backup_flydigi,          restore_flydigi),
    "Ghostty":          ("Terminal", backup_ghostty,          restore_ghostty),
    "Helix":            ("Editor",   backup_helix,            restore_helix),
    "IntelliJ":         ("Editor",   backup_intellij,         restore_intellij),
    "Notable":          ("Notes",    backup_notable,          restore_notable),
    "PowerShell":       ("Terminal", backup_powershell,       restore_powershell),
    "RStudio":          ("Editor",   backup_rstudio,          restore_rstudio),
    "Starship":         ("Terminal", backup_starship,         restore_starship),
    "VIM":              ("Editor",   backup_vim,              restore_vim),
    "VSCode / Cursor":  ("Editor",   backup_vscode,           restore_vscode),
    "Windows Terminal": ("Terminal", backup_windows_terminal, restore_windows_terminal),
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    ordered = sorted(ITEMS.items(), key=lambda kv: (CATEGORY_ORDER.index(kv[1][0]), kv[0]))
    labeled = [(name, f"{category:<8} / {name}") for name, (category, _, _) in ordered]

    choices = [Separator("=== Backup ===")]
    choices += [Choice(("backup", name), name=label) for name, label in labeled]
    choices.append(Separator("=== Restore ==="))
    choices += [Choice(("restore", name), name=label) for name, label in labeled]

    selected = inquirer.checkbox(
        message="Select operations:",
        choices=choices,
    ).execute()
    if not selected:
        sys.exit(0)

    for operation, name in selected:
        _, backup_fn, restore_fn = ITEMS[name]
        fn = backup_fn if operation == "backup" else restore_fn
        fn()
