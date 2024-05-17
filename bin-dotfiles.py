import os
import platform
import requests
import shutil
import sys

# ------------------------------------------------------------------------------
# Functions - Folders and IPs
# ------------------------------------------------------------------------------
MAC = "192.168.0.14:3000"
USER = None

def is_linux():
    """Check if current system is WSL / Linux."""
    return platform.system() == "Linux"

def is_mac():
    """Check if current system is MacOs."""
    return platform.system() == "Darwin"

def is_win():
    """Check if current system is Windows."""
    return is_linux()

def user():
    global USER
    """Username executing this script."""
    if USER is None:
        USER = os.popen("whoami").read().strip()
    return USER

def unix_home(path):
    """Path of Unix home directory (Linux and Mac)."""
    home = os.environ["HOME"]
    return f"{home}/{path}"

def win_roaming(path):
    """Path of Windows AppData/Roaming directory."""
    return f"/mnt/c/Users/{user()}/AppData/Roaming/{path}"

def win_local(path):
    """Path of Windows AppData/Local directory."""
    return f"/mnt/c/Users/{user()}/AppData/Local/{path}"

def mac_library(path):
    """Path of Mac Library directory."""
    return unix_home("Library/") + path

def mac_app_support(path):
    """Path of Mac Application Support directory."""
    return mac_library("Application Support/") + path

def dotfiles(path=None):
    """Path of dotfiles backup directory."""
    base = "./dotfiles"
    if path is None:
        return base
    else:
        return base + "/" + path

# ------------------------------------------------------------------------------
# Functions - Transfer
# ------------------------------------------------------------------------------

def log_transfer(kind_source, kind_target, source_file, target_file):
    """Logs a transfer operation."""
    print()
    print(f"{kind_source} -> {kind_target}")
    print(f"  {source_file} -> {target_file}")

def d2d(source, target):
    """Copies a local directory to a local target."""
    log_transfer("Dir", "Dir", source, target)

    # create directory if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)

def f2f(source, target):
    """Copies a local file to a local target."""
    log_transfer("File", "File", source, target)

    # create directory if necessary
    target_dirname = os.path.dirname(target)
    if not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    shutil.copyfile(source, target)

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

def backup():
    # remove synced files
    if os.path.exists(dotfiles()):
        shutil.rmtree(dotfiles())

    # Custom Scripts
    f2f(unix_home("scripts/alias.sh"), dotfiles("scripts/alias.sh"))

    # ASDF
    f2f(unix_home(".tool-versions"), dotfiles(".tool-versions"))

    # Helix
    f2f(unix_home(".config/helix/config.toml"), dotfiles("helix/config.toml"))
    f2f(unix_home(".config/helix/languages.toml"), dotfiles("helix/languages.toml"))

    # IntelliJ
    if is_win():
        d2d(win_roaming("JetBrains/IdeaIC2023.2/keymaps"), dotfiles("intellij/keymaps"))
        f2f(win_roaming("JetBrains/IdeaIC2023.2/options/editor.xml"), dotfiles("intellij/options/editor.xml"))
        f2f(win_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml"), dotfiles("intellij/options/editor-font.xml"))
        f2f(win_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml"), dotfiles("intellij/options/window.layouts.xml"))

    # VSCode
    if is_win():
        f2f(win_roaming("Code/User/keybindings.json"), dotfiles("vscode/keybindings.json"))
        f2f(win_roaming("Code/User/settings.json"), dotfiles("vscode/settings.json"))

    # VIM
    f2f(unix_home(".vimrc"), dotfiles(".vimrc"))

    # Terminal
    if is_win():
        f2f(win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"), dotfiles("windows-terminal/settings.json"))

def restore():
    # Custom Scripts
    f2f(dotfiles("scripts/alias.sh"), unix_home("scripts/alias.sh"))

    # ASDF
    f2f(dotfiles(".tool-versions"), unix_home(".tool-versions"))

    # Helix
    d2d(dotfiles("helix"), unix_home(".config/helix"))
    if is_win():
        d2d(dotfiles("helix"), win_roaming("helix"))

    # IntelliJ
    if is_win():
        d2d(dotfiles("intellij"), win_roaming("JetBrains/IdeaIC2023.2"))

    # VSCode
    if is_win():
        d2d(dotfiles("vscode"), win_roaming("Code/User"))
    if is_mac():
        d2d(dotfiles("vscode"), mac_app_support("Code/User"))

    # VIM
    f2f(dotfiles(".vimrc"), unix_home(".vimrc"))

    # Terminal
    if is_win():
        d2d(dotfiles("windows-terminal"), win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/"))

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
