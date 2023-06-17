import os
import shutil

def user():
    """User to connect to remote host."""
    return os.environ["REMOTE_USER"]

def host():
    """Remote host to connect to."""
    return os.environ["REMOTE_HOST"]

def appdata():
    """Windows appdata folder."""
    return os.environ["APPDATA"]

def local_appdata():
    """Windows local appdata folder."""
    return os.environ["LOCALAPPDATA"]

def sync_remote(file):
    """Syncs a remote file to the local backup."""
    print("Remote: {}".format(file))

    # create folder if necessary
    file_dirname = "dotfiles/" + os.path.dirname(file)
    file_basename = os.path.basename(file)
    if file_dirname != "" and not os.path.exists(file_dirname):
        os.makedirs(file_dirname)

    # execute sync command
    command = "scp {}@{}:~/{} {}/{} > out".format(user(), host(), file, file_dirname, file_basename)
    os.system(command)

def sync_local_folder(source, target):
    """Syncs a local folder to the local backup."""
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)

def sync_local_file(source, target):
    """Syncs a local file to the local backup."""
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    target_dirname = os.path.dirname(target)
    if not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    shutil.copyfile(source, target)

if __name__ == "__main__":
    print("Remote: {}@{}".format(user(), host()))

    # remove synced files
    shutil.rmtree("dotfiles")

    # sync remote to local
    sync_remote("scripts/alias.sh")
    sync_remote(".vimrc")
    sync_remote(".config/helix/config.toml")
    sync_remote(".config/helix/languages.toml")

    # sync local to local
    sync_local_file(appdata() + "/Code/User/keybindings.json", "dotfiles/vscode/keybindings.json")
    sync_local_file(appdata() + "/Code/User/settings.json", "dotfiles/vscode/settings.json")
    sync_local_folder(appdata() + "/JetBrains/IdeaIC2023.1/keymaps", "dotfiles/intellij/keymaps")
    sync_local_file(appdata() + "/JetBrains/IdeaIC2023.1/options/editor.xml", "dotfiles/intellij/options/editor.xml")
    sync_local_file(appdata() + "/JetBrains/IdeaIC2023.1/options/editor-font.xml", "dotfiles/intellij/options/editor-font.xml")
    sync_local_file(appdata() + "/JetBrains/IdeaIC2023.1/options/window.layouts.xml", "dotfiles/intellij/options/window.layouts.xml")
    sync_local_file(local_appdata() + "/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json", "dotfiles/windows-terminal/settings.json")

    # distribute local to local
    sync_local_folder("dotfiles/.config/helix", appdata() + "/helix")

    # remove temp files created
    os.remove("out")
