import os
import requests
import shutil
import sys

# ------------------------------------------------------------------------------
# Functions - Folders and IPs
# ------------------------------------------------------------------------------
MAC_IP = "192.168.0.14"
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

def wsl_home(path):
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

def local_file_to_remote(remote, source, target):
    """Copies a local file to a remote target using HTTP POST."""
    log_transfer("File", f"Remote ({remote})", source, target)
    with open(source, "r") as f:
        content = f.read()
    try:
        requests.post(f"http://{remote}/upload", json={"path": target, "content": content}, timeout=1)
    except Exception as e:
        print(f"[!] Failed to communicate with remote host: {repr(e)}")

def local_dir_to_remote(remote, source, target):
    """Copies a local directory to a remote target using HTTP POST."""
    log_transfer("Dir", f"Remote ({remote})", source, target)

    for root, _, files in os.walk(source):
        for file in files:
            source_file = f"{root}/{file}"
            target_file = f"{target}/{file}"
            local_file_to_remote(remote, source_file, target_file)

def local_dir_to_local(source, target):
    """Copies a local directory to a local target."""
    log_transfer("Dir", "Dir", source, target)

    # create directory if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)

def local_file_to_local(source, target):
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
    local_file_to_local(wsl_home("scripts/alias.sh"), dotfiles("scripts/alias.sh"))

    # Helix
    local_file_to_local(wsl_home(".config/helix/config.toml"), dotfiles("helix/config.toml"))
    local_file_to_local(wsl_home(".config/helix/languages.toml"), dotfiles("helix/languages.toml"))

    # IntelliJ
    local_dir_to_local(win_roaming("JetBrains/IdeaIC2023.2/keymaps"), dotfiles("intellij/keymaps"))
    local_file_to_local(win_roaming("JetBrains/IdeaIC2023.2/options/editor.xml"), dotfiles("intellij/options/editor.xml"))
    local_file_to_local(win_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml"), dotfiles("intellij/options/editor-font.xml"))
    local_file_to_local(win_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml"), dotfiles("intellij/options/window.layouts.xml"))

    # VSCode
    local_file_to_local(win_roaming("Code/User/keybindings.json"), dotfiles("vscode/keybindings.json"))
    local_file_to_local(win_roaming("Code/User/settings.json"), dotfiles("vscode/settings.json"))

    # VIM
    local_file_to_local(wsl_home(".vimrc"), dotfiles(".vimrc"))

    # Windows Terminal
    local_file_to_local(win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"), dotfiles("windows-terminal/settings.json"))

def restore():
    # Aliases
    local_file_to_local(dotfiles("scripts/alias.sh"), wsl_home("scripts/alias.sh"))
    local_file_to_remote(MAC_IP, dotfiles("scripts/alias.sh"), "~/scripts/alias.sh")

    # Helix
    helix = dotfiles("helix")
    local_dir_to_local(helix, wsl_home(".config/helix"))
    local_dir_to_local(helix, win_roaming("helix"))
    local_dir_to_remote(MAC_IP, helix, "~/.config/helix")

    # IntelliJ
    local_dir_to_local(dotfiles("intellij"), win_roaming("JetBrains/IdeaIC2023.2"))

    # VSCode
    local_dir_to_local(dotfiles("vscode"), win_roaming("Code/User"))

    # VIM
    local_file_to_local(dotfiles(".vimrc"), wsl_home(".vimrc"))

    # Windows Terminal
    local_dir_to_local(dotfiles("windows-terminal"), win_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/"))

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