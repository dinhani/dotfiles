import os
import platform
import shutil
import sys

# ------------------------------------------------------------------------------
# Classes
# ------------------------------------------------------------------------------
class File(os.PathLike):
    def __init__(self, path: str) -> None:
        self.path = path

    def __fspath__(self) -> str:
        return str(self)

    def __str__(self) -> str:
        return self.path

    def __rshift__(self, other) -> None:
        """Copy a source to a target. Automatically detects if source is a file or directory."""
        if os.path.isfile(self):
            self.cp_file(other)
        else:
            self.cp_dir(other)

    def cp_dir(self, target: str):
        """Copy a local directory to a local target."""
        try:
            log_transfer("Dir", "Dir", self, target)

            # create directory if necessary
            if not os.path.exists(target):
                os.makedirs(target)

            shutil.copytree(self, target, dirs_exist_ok=True)
        except Exception as e:
            log_error("Failed to copy directory", e)

    def cp_file(self, target: str):
        """Copy a local file to a local target."""
        try:
            log_transfer("File", "File", self, target)

            # create directory if necessary
            target_dirname = os.path.dirname(target)
            if not os.path.exists(target_dirname):
                os.makedirs(target_dirname)

            shutil.copyfile(self, target)
        except Exception as e:
            log_error("Failed to copy file", e)

# ------------------------------------------------------------------------------
# Functions - OS/Directories
# ------------------------------------------------------------------------------
USER = None

def is_linux() -> bool:
    """Check if current system is WSL / Linux."""
    return platform.system() == "Linux"

def is_mac() -> bool:
    """Check if current system is MacOs."""
    return platform.system() == "Darwin"

def is_win() -> bool:
    """Check if current system is Windows."""
    return os.path.exists("/mnt/c/")

def user() -> str:
    global USER
    """Username executing this script."""
    if USER is None:
        USER = os.popen("whoami").read().strip()
    return USER

def unix_home(path: str) -> File:
    """Path of Unix home directory (Linux and Mac)."""
    home = os.environ["HOME"]
    return File(f"{home}/{path}")

def win_root(path: str) -> File:
    """Path of Windows root directory."""
    return File(f"/mnt/c/{path}")

def win_home(path: str) -> File:
    """Path of Windows home directory."""
    return File(f"/mnt/c/Users/{user()}/{path}")

def win_roaming(path: str) -> File:
    """Path of Windows AppData/Roaming directory."""
    return File(f"/mnt/c/Users/{user()}/AppData/Roaming/{path}")

def win_local(path: str) -> File:
    """Path of Windows AppData/Local directory."""
    return File(f"/mnt/c/Users/{user()}/AppData/Local/{path}")

def win_prog32(path: str) -> File:
    """Path of Windows Program Files (x86) directory."""
    return File(f"/mnt/c/Program Files (x86)/{path}")

def win_prog64(path: str) -> File:
    """Path of Windows Program Files (x64) directory."""
    return File(f"/mnt/c/Program Files/{path}")

def win_emu(path: str) -> File:
    """Path of Windows emulators directory."""
    emu_dir = str(win_root("_emu"))
    return File(f"{emu_dir}/{path}")

def mac_app_support(path: str) -> File:
    """Path of Mac Application Support directory."""
    base = unix_home("Library/Application Support/")
    return File(f"{base}/{path}")

def dotfiles(path: str = None) -> File:
    """Path of dotfiles backup directory."""
    base = "./dotfiles"
    if path is None:
        return File(base)
    else:
        return File(f"{base}/{path}")

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
    if os.path.exists(dotfiles()):
        shutil.rmtree(dotfiles())

    # --------------------------------------------------------------------------
    # Unix
    # --------------------------------------------------------------------------
    # Aliases
    unix_home("scripts/alias.sh") >> dotfiles("scripts/alias.sh")

    # ASDF
    unix_home(".tool-versions") >> dotfiles("asdf/.tool-versions")

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
        win_local("LGHUB/settings.db") >> dotfiles("lghub/settings.db")
        win_prog64("FlydigiSpaceStation/config/share/") >> dotfiles("flydigi/share")

        # Emulators
        win_emu("ares/settings.bml") >> dotfiles("ares/settings.bml")
        win_roaming("Dolphin Emulator/Config") >> dotfiles("dolphin")
        win_emu("cemu2/controllerProfiles") >> dotfiles("cemu2/controllerProfiles")
        win_emu("cemu2/settings.xml") >> dotfiles("cemu2/settings.xml")
        win_emu("mame/mame.ini") >> dotfiles("mame/mame.ini")
        win_emu("mame/plugin.ini") >> dotfiles("mame/plugin.ini")
        win_emu("mame/ui.ini") >> dotfiles("mame/ui.ini")
        win_emu("pcsx2/inis/PCSX2.ini") >> dotfiles("pcsx2/inis/PCSX2.ini")
        win_emu("project64/Config/Project64.cfg") >> dotfiles("project64/Config/Project64.cfg")
        win_emu("retroarch/retroarch.cfg") >> dotfiles("retroarch/retroarch.cfg")
        win_emu("retroarch/retroarch-core-options.cfg") >> dotfiles("retroarch/retroarch-core-options.cfg")
        win_emu("retroarch/retroarch_qt.cfg") >> dotfiles("retroarch/retroarch_qt.cfg")
        win_roaming("Ryujinx/Config.json") >> dotfiles("ryujinx/Config.json")

        # IntelliJ
        win_roaming("JetBrains/IdeaIC2023.2/keymaps") >> dotfiles("intellij/keymaps")
        win_roaming("JetBrains/IdeaIC2023.2/options/editor.xml") >> dotfiles("intellij/options/editor.xml")
        win_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml") >> dotfiles("intellij/options/editor-font.xml")
        win_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml") >> dotfiles("intellij/options/window.layouts.xml")

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
    # Aliases
    dotfiles("scripts/alias.sh") >> unix_home("scripts/alias.sh")

    # ASDF
    dotfiles("asdf/.tool-versions") >> unix_home(".tool-versions")

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
        dotfiles("lghub") >> win_local("LGHUB")

        # Emulators
        dotfiles("ares") >> win_emu("ares")
        dotfiles("cemu2") >> win_emu("cemu2")
        dotfiles("dolphin") >> win_roaming("Dolphin Emulator/Config")
        dotfiles("mame") >> win_emu("mame")
        dotfiles("pcsx2") >> win_emu("pcsx2")
        dotfiles("project64") >> win_emu("project64")
        dotfiles("retroarch") >> win_emu("retroarch")
        dotfiles("ryujinx") >> win_roaming("Ryujinx")

        # Helix
        dotfiles("helix") >> win_roaming("helix")

        # IntelliJ
        dotfiles("intellij") >> win_roaming("JetBrains/IdeaIC2023.2")

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

    # remove temp files created
    if os.path.exists("out"):
        os.remove("out")
