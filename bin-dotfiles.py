import os
import requests
import shutil
import sys

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

def remote_user():
    """User to connect to remote host."""
    return os.environ["REMOTE_USER"]

def remote_host():
    """Remote host to connect to."""
    return os.environ["REMOTE_HOST"]

def appdata_roaming(path):
    """Path inside Windows AppData/Roaming directory."""
    return os.environ["APPDATA"] + "/" + path

def appdata_local(path):
    """Path inside Windows AppData/Local directory."""
    return os.environ["LOCALAPPDATA"] + "/" + path

def wsl_home(path):
    """Path inside WSL2 Home directory."""
    return os.environ["HOME"] + "/" + path

def dotfiles(path=None):
    """Path inside dotfiles directory."""
    base = "./dotfiles"
    if path is None:
        return base
    else:
        return base + "/" + path

def local_file_to_remote(source, target):
    """Copies a local file to a remote target using HTTP POST."""
    print("{:<16}: {} -> {}".format("File -> Remote", source, target))
    with open(source, "r") as f:
        content = f.read()
    requests.post(f"http://{remote_host()}/upload", json={"path": target, "content": content})

def local_dir_to_remote(source, target):
    """Copies a local directory to a remote target using HTTP POST."""
    print("{:<16}: {} -> {}".format("Dir  -> Remote", source, target))

    for root, _, files in os.walk(source):
        for file in files:
            source_file = f"{root}/{file}"
            target_file = f"{target}/{file}"
            local_file_to_remote(source_file, target_file)

def local_dir_to_local(source, target):
    """Copies a local directory to a local target."""
    print("{:<16}: {} -> {}".format("Dir  -> Dir", source, target))

    # create directory if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)

def local_file_to_local(source, target):
    """Copies a local file to a local target."""
    print("{:<16}: {} -> {}".format("File -> File", source, target))

    # create directory if necessary
    target_dirname = os.path.dirname(target)
    if not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    shutil.copyfile(source, target)

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

DIR_INTELLIJ = "JetBrains/IdeaIC2023.2"

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
    local_dir_to_local(appdata_roaming("JetBrains/IdeaIC2023.2/keymaps"), dotfiles("intellij/keymaps"))
    local_file_to_local(appdata_roaming("JetBrains/IdeaIC2023.2/options/editor.xml"), dotfiles("intellij/options/editor.xml"))
    local_file_to_local(appdata_roaming("JetBrains/IdeaIC2023.2/options/editor-font.xml"), dotfiles("intellij/options/editor-font.xml"))
    local_file_to_local(appdata_roaming("JetBrains/IdeaIC2023.2/options/window.layouts.xml"), dotfiles("intellij/options/window.layouts.xml"))

    # VSCode
    local_file_to_local(appdata_roaming("Code/User/keybindings.json"), dotfiles("vscode/keybindings.json"))
    local_file_to_local(appdata_roaming("Code/User/settings.json"), dotfiles("vscode/settings.json"))

    # VIM
    local_file_to_local(wsl_home(".vimrc"), dotfiles(".vimrc"))

    # Windows Terminal
    local_file_to_local(appdata_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"), dotfiles("windows-terminal/settings.json"))

def restore():
    # Aliases
    local_file_to_local(dotfiles("scripts/alias.sh"), wsl_home("scripts/alias.sh"))
    local_file_to_remote(dotfiles("scripts/alias.sh"), "~/scripts/alias.sh")

    # Helix
    helix = dotfiles("helix")
    local_dir_to_local(helix, wsl_home(".config/helix"))
    local_dir_to_local(helix, appdata_roaming("helix"))
    local_dir_to_remote(helix, "~/.config/helix")

    # IntelliJ
    local_dir_to_local(dotfiles("intellij"), appdata_roaming("JetBrains/IdeaIC2023.2"))

    # VSCode
    local_dir_to_local(dotfiles("vscode"), appdata_roaming("Code/User"))

    # VIM
    local_file_to_local(dotfiles(".vimrc"), wsl_home(".vimrc"))

    # Windows Terminal
    local_dir_to_local(dotfiles("windows-terminal"), appdata_local("Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/"))

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