import os
import platform
import shutil
import sys

# ------------------------------------------------------------------------------
# Classes
# ------------------------------------------------------------------------------
class Source(os.PathLike):
    def __init__(self, path: str) -> None:
        self.path = path

    def __rshift__(self, other) -> None:
        """Copies a source to a target. Automatically detects if source is a file or directory."""
        if os.path.isfile(self):
            self.cp_file(other)
        else:
            self.cp_dir(other)

    def __fspath__(self) -> str:
        return str(self)

    def __str__(self) -> str:
        return self.path

    def cp_dir(self, target: str):
        """Copies a local directory to a local target."""
        try:
            log_transfer("Dir", "Dir", self, target)

            # create directory if necessary
            if not os.path.exists(target):
                os.makedirs(target)

            shutil.copytree(self, target, dirs_exist_ok=True)
        except Exception as e:
            log_error("Failed to copy directory", e)

    def cp_file(self, target: str):
        """Copies a local file to a local target."""
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

def unix_home(path: str) -> Source:
    """Path of Unix home directory (Linux and Mac)."""
    home = os.environ["HOME"]
    return Source(f"{home}/{path}")

def win_root(path: str) -> Source:
    """Path of Windows root directory."""
    return Source(f"/mnt/c/{path}")

def win_home(path: str) -> Source:
    """Path of Windows home directory."""
    return Source(f"/mnt/c/Users/{user()}/{path}")

def win_roaming(path: str) -> Source:
    """Path of Windows AppData/Roaming directory."""
    return Source(f"/mnt/c/Users/{user()}/AppData/Roaming/{path}")

def win_local(path: str) -> Source:
    """Path of Windows AppData/Local directory."""
    return Source(f"/mnt/c/Users/{user()}/AppData/Local/{path}")

def mac_app_support(path: str) -> Source:
    """Path of Mac Application Support directory."""
    return unix_home("Library/Application Support/") + path

def dotfiles(path: str = None) -> Source:
    """Path of dotfiles backup directory."""
    base = "./dotfiles"
    if path is None:
        return Source(base)
    else:
        return Source(f"{base}/{path}")

# ------------------------------------------------------------------------------
# Functions - Transfer
# ------------------------------------------------------------------------------

def log_transfer(kind_source, kind_target, source_file, target_file):
    """Logs a transfer operation."""
    print()
    print(f"{kind_source} -> {kind_target}")
    print(f"  {source_file} -> {target_file}")

def log_error(message, exception):
    """Logs an error message."""
    print(f"  [!] {message}: {exception}")

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

def backup():
    # remove synced files
    if os.path.exists(dotfiles()):
        shutil.rmtree(dotfiles())

    # Custom Scripts
    unix_home("scripts/alias.sh") >> dotfiles("scripts/alias.sh")

    # ASDF
    unix_home(".tool-versions") >> dotfiles(".tool-versions")

    # Helix
    unix_home(".config/helix/config.toml") >> dotfiles("helix/config.toml")
    unix_home(".config/helix/languages.toml") >> dotfiles("helix/languages.toml")

    # IntelliJ
    if is_win():
        win_roaming("JetBrains/IdeaIC2023.2/keymaps") >> dotfiles("intellij/keymaps")
        win_roaming("JetBrains/IdeaIC2023.2/options/editor.xml") >> dotfiles("intellij/options/editor.xml")
        win_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml") >> dotfiles("intellij/options/editor-font.xml")
        win_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml") >> dotfiles("intellij/options/window.layouts.xml")

    # Notable
    if is_win():
        win_home(".notable.json") >> dotfiles(".notable.json")

    # VSCode
    if is_win():
        win_roaming("Code/User/keybindings.json") >> dotfiles("vscode/keybindings.json")
        win_roaming("Code/User/settings.json") >> dotfiles("vscode/settings.json")

    # VIM
    unix_home(".vimrc") >> dotfiles(".vimrc")

    # Terminal
    if is_win():
        win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json") >> dotfiles("windows-terminal/settings.json")

    # Emulators
    if is_win():
        win_roaming("Dolphin Emulator/Config") >> dotfiles("emu/dolphin")
        win_root("_emu/pcsx2/inis/PCSX2.ini") >> dotfiles("emu/PCSX2.ini")

def restore():
    # Custom Scripts
    dotfiles("scripts/alias.sh") >> unix_home("scripts/alias.sh")

    # ASDF
    dotfiles(".tool-versions") >> unix_home(".tool-versions")

    # Helix
    dotfiles("helix") >> unix_home(".config/helix")
    if is_win():
        dotfiles("helix") >> win_roaming("helix")

    # IntelliJ
    if is_win():
        dotfiles("intellij") >> win_roaming("JetBrains/IdeaIC2023.2")

    # Notable
    if is_win():
        dotfiles(".notable.json") >> win_home(".notable.json")

    # VSCode
    if is_win():
        dotfiles("vscode") >> win_roaming("Code/User")
    if is_mac():
        dotfiles("vscode") >> mac_app_support("Code/User")

    # VIM
    dotfiles(".vimrc") >> unix_home(".vimrc")

    # Terminal
    if is_win():
        dotfiles("windows-terminal") >> win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/")

    # Emulators
    if is_win():
        dotfiles("emu/dolphin") >> win_roaming("Dolphin Emulator/Config")
        dotfiles("emu/PCSX2.ini") >> win_root("_emu/pcsx2/inis/PCSX2.ini")

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
