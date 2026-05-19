import os
import platform
import shutil
import sys
from pathlib import Path

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
# Functions - Transfer
# ------------------------------------------------------------------------------

def log_transfer(kind_source, kind_target, source_file, target_file):
    """Log a transfer operation."""
    print()
    print(f"{kind_source} -> {kind_target}")
    print(f"  {source_file} -> {target_file}")

def log_error(message, exception):
    """Log an error message."""
    print(f"  [!] {message}: {exception}")

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

def backup():
    """Backup dotfiles from machine to local directory."""

    # remove synced files
    if dotfiles().exists():
        shutil.rmtree(dotfiles())

    # --------------------------------------------------------------------------
    # Unix
    # --------------------------------------------------------------------------
    # Ghostty
    unix_home(".config/ghostty/config") >> dotfiles("ghostty/config")

    # Helix
    unix_home(".config/helix/config.toml") >> dotfiles("helix/config.toml")
    unix_home(".config/helix/languages.toml") >> dotfiles("helix/languages.toml")

    # Starship
    unix_home(".config/starship.toml") >> dotfiles("starship/starship.toml")

    # VIM
    unix_home(".vimrc") >> dotfiles("vim/.vimrc")

    # --------------------------------------------------------------------------
    # Windows
    # --------------------------------------------------------------------------
    if is_win():
        # Aliases
        win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1") >> dotfiles("powershell/Microsoft.PowerShell_profile.ps1")

        # Devices
        win_prog64("FlydigiSpaceStation/config/share/") >> dotfiles("flydigi/share")

        # IntelliJ
        win_roaming("JetBrains/IntelliJIdea2025.3/keymaps") >> dotfiles("intellij/keymaps")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/editor.xml") >> dotfiles("intellij/options/editor.xml")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/editor-font.xml") >> dotfiles("intellij/options/editor-font.xml")
        win_roaming("JetBrains/IntelliJIdea2025.3/options/window.layouts.xml") >> dotfiles("intellij/options/window.layouts.xml")

        # Notable
        win_home(".notable.json") >> dotfiles("notable/.notable.json")

        # RStudio
        win_roaming("RStudio/config.json") >> dotfiles("rstudio/config.json")
        win_roaming("RStudio/keybindings") >> dotfiles("rstudio/keybindings")

        # VSCode
        win_roaming("Code/User/keybindings.json") >> dotfiles("vscode/keybindings.json")
        win_roaming("Code/User/settings.json") >> dotfiles("vscode/settings.json")

        # Terminal
        win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json") >> dotfiles("windows-terminal/settings.json")

def restore():
    """Restore dotfiles from local directory to machine."""

    # --------------------------------------------------------------------------
    # Unix
    # --------------------------------------------------------------------------
    # Ghostty
    dotfiles("ghostty") >> unix_home(".config/ghostty")

    # Helix
    dotfiles("helix") >> unix_home(".config/helix")

    # Starship
    dotfiles("starship/starship.toml") >> unix_home(".config/starship.toml")

    # VIM
    dotfiles("vim/.vimrc") >> unix_home(".vimrc")

    # --------------------------------------------------------------------------
    # Windows
    # --------------------------------------------------------------------------
    if is_win():
        # Aliases
        dotfiles("powershell/Microsoft.PowerShell_profile.ps1") >> win_home("Documents/PowerShell/Microsoft.PowerShell_profile.ps1")

        # Devices
        dotfiles("flydigi") >> win_prog64("FlydigiSpaceStation/config")

        # Helix
        dotfiles("helix") >> win_roaming("helix")

        # IntelliJ
        dotfiles("intellij") >> win_roaming("JetBrains/IntelliJIdea2025.3")

        # Notable
        dotfiles("notable/.notable.json") >> win_home(".notable.json")

        # RStudio
        dotfiles("rstudio") >> win_roaming("RStudio")

        # Terminal
        dotfiles("windows-terminal") >> win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/")

        # VSCode / Cursor
        dotfiles("vscode") >> win_roaming("Code/User")
        dotfiles("vscode") >> win_roaming("Cursor/User")

    # --------------------------------------------------------------------------
    # Mac
    # --------------------------------------------------------------------------
    if is_mac():
        # IntelliJ
        dotfiles("intellij") >> mac_app_support("JetBrains/IntelliJIdea2025.3")

        # VSCode / Cursor
        dotfiles("vscode") >> mac_app_support("Code/User")
        dotfiles("vscode") >> mac_app_support("Cursor/User")

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
if __name__ == "__main__":
    # parse command
    if len(sys.argv) < 2:
        print("Command not specified. Pass `backup` or `restore` as argument.")
        exit(0)
    command = sys.argv[1]
    if command not in ["backup", "restore"]:
        print(f"Unknown command: {command}")

    # execute command
    match command:
        case "backup":
            backup()
        case "restore":
            restore()
