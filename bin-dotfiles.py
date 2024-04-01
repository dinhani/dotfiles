import os
import requests
import shutil
import sys

# ------------------------------------------------------------------------------
# Functions - Folders and IPs
# ------------------------------------------------------------------------------
MAC = "192.168.0.14:3000"
USER = None

def user():
    global USER
    """Username executing this script."""
    if USER is None:
        USER = os.popen("whoami").read().strip()
    return USER

def win_roaming(path):
    """Path of Windows AppData/Roaming directory."""
    return f"/mnt/c/Users/{user()}/AppData/Roaming/{path}"

def win_local(path):
    """Path of Windows AppData/Local directory."""
    return f"/mnt/c/Users/{user()}/AppData/Local/{path}"

def wsl(path):
    """Path of WSL2 Home directory."""
    return f"/home/{user()}/{path}"

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

def r2f(remote, source, target):
    """Copies a remote file to a local target."""
    log_transfer(f"Remote ({remote})", "File", source, target)
    try:
        response = requests.post(f"http://{remote}/download", json={"path": source}, timeout=1)
        with open(target, "w") as f:
            f.write(response.text)
    except Exception as e:
        print(f"[!] Failed to communicate with remote host: {repr(e)}")

def d2r(source, remote, target):
    """Copies a local directory to a remote target."""
    log_transfer("Dir", f"Remote ({remote})", source, target)

    for root, _, files in os.walk(source):
        for file in files:
            source_file = f"{root}/{file}"
            target_file = f"{target}/{file}"
            f2r(source_file, remote, target_file)

def f2r(source, remote, target):
    """Copies a local file to a remote target using HTTP POST."""
    log_transfer("File", f"Remote ({remote})", source, target)
    with open(source, "r") as f:
        content = f.read()
    try:
        requests.post(f"http://{remote}/upload", json={"path": target, "content": content}, timeout=1)
    except Exception as e:
        print(f"[!] Failed to communicate with remote host: {repr(e)}")

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

    # Aliases
    f2f(wsl("scripts/alias.sh"), dotfiles("scripts/alias.sh"))

    # Helix
    f2f(wsl(".config/helix/config.toml"), dotfiles("helix/config.toml"))
    f2f(wsl(".config/helix/languages.toml"), dotfiles("helix/languages.toml"))

    # IntelliJ
    d2d(win_roaming("JetBrains/IdeaIC2023.2/keymaps"), dotfiles("intellij/keymaps"))
    f2f(win_roaming("JetBrains/IdeaIC2023.2/options/editor.xml"), dotfiles("intellij/options/editor.xml"))
    f2f(win_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml"), dotfiles("intellij/options/editor-font.xml"))
    f2f(win_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml"), dotfiles("intellij/options/window.layouts.xml"))

    # VSCode
    f2f(win_roaming("Code/User/keybindings.json"), dotfiles("vscode/keybindings.json"))
    f2f(win_roaming("Code/User/settings.json"), dotfiles("vscode/settings.json"))

    # VIM
    f2f(wsl(".vimrc"), dotfiles(".vimrc"))

    # Terminal
    f2f(win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"), dotfiles("windows-terminal/settings.json"))

def restore():
    # Aliases
    f2f(dotfiles("scripts/alias.sh"), wsl("scripts/alias.sh"))
    f2r(dotfiles("scripts/alias.sh"), MAC, "~/scripts/alias.sh")

    # Helix
    d2d(dotfiles("helix"), wsl(".config/helix"))
    d2d(dotfiles("helix"), win_roaming("helix"))
    d2r(dotfiles("helix"), MAC, "~/.config/helix")

    # IntelliJ
    d2d(dotfiles("intellij"), win_roaming("JetBrains/IdeaIC2023.2"))

    # VSCode
    d2d(dotfiles("vscode"), win_roaming("Code/User"))

    # VIM
    f2f(dotfiles(".vimrc"), wsl(".vimrc"))

    # Terminal
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