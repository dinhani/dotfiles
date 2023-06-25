import os
import shutil

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

def user():
    """User to connect to remote host."""
    return os.environ["REMOTE_USER"]

def host():
    """Remote host to connect to."""
    return os.environ["REMOTE_HOST"]

def appdata(path):
    """Path inside Windows appdata folder."""
    return os.environ["APPDATA"] + "/" + path

def local_appdata(path):
    """Path inside Windows local appdata folder."""
    return os.environ["LOCALAPPDATA"] + "/" + path

def dotfiles(path = None):
    """Path inside dotfiles folder."""
    base = "./dotfiles"
    if path is None:
        return base
    else:
        return base + "/" + path

def copy_remote_file(file, target):
    """Copies a remote file to a local target."""
    print("Remote: {}".format(file))

    # create folder if necessary
    target_dirname = os.path.dirname(target)
    target_basename = os.path.basename(target)
    if target_dirname != "" and not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    # execute sync command
    command = "scp {}@{}:~/{} {}/{} > out".format(user(), host(), file, target_dirname, target_basename)
    os.system(command)

def copy_local_folder(source, target):
    """Copies a local folder to a local target."""
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)

def copy_local_file(source, target):
    """Copies a local file to a local target."""
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    target_dirname = os.path.dirname(target)
    if not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    shutil.copyfile(source, target)

# ------------------------------------------------------------------------------
# Execution
# ------------------------------------------------------------------------------

if __name__ == "__main__":
    print("Remote: {}@{}".format(user(), host()))

    # remove synced files
    if os.path.exists(dotfiles()):
        shutil.rmtree(dotfiles())

    # sync remote to local
    copy_remote_file("scripts/alias.sh", dotfiles("scripts/alias.sh"))
    copy_remote_file(".vimrc", dotfiles(".vimrc"))
    copy_remote_file(".config/helix/config.toml", dotfiles(".config/helix/config.toml"))
    copy_remote_file(".config/helix/languages.toml", dotfiles(".config/helix/languages.toml"))

    # sync local to local
    copy_local_file(appdata("/Code/User/keybindings.json"), dotfiles("vscode/keybindings.json"))
    copy_local_file(appdata("/Code/User/settings.json"), dotfiles("vscode/settings.json"))
    copy_local_folder(appdata("/JetBrains/IdeaIC2023.1/keymaps"), dotfiles("intellij/keymaps"))
    copy_local_file(appdata("/JetBrains/IdeaIC2023.1/options/editor.xml"), dotfiles("intellij/options/editor.xml"))
    copy_local_file(appdata("/JetBrains/IdeaIC2023.1/options/editor-font.xml"), dotfiles("intellij/options/editor-font.xml"))
    copy_local_file(appdata("/JetBrains/IdeaIC2023.1/options/window.layouts.xml"), dotfiles("intellij/options/window.layouts.xml"))
    copy_local_file(local_appdata("/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"), dotfiles("windows-terminal/settings.json"))

    # distribute local to local
    copy_local_folder(dotfiles(".config/helix"), appdata("helix"))

    # remove temp files created
    os.remove("out")
