# ------------------------------------------------------------------------------
# Libs
# ------------------------------------------------------------------------------
import os
import shutil

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------


def user():
    return os.environ["REMOTE_USER"]


def host():
    return os.environ["REMOTE_HOST"]


def appdata():
    return os.environ["APPDATA"]


def sync_remote(file):
    print("Remote: {}".format(file))

    # create folder if necessary
    file_dirname = "dotfiles/" + os.path.dirname(file)
    file_basename = os.path.basename(file)
    if file_dirname != "" and not os.path.exists(file_dirname):
        os.makedirs(file_dirname)

    # execute sync command
    command = "scp {}@{}:~/{} {}/{} > out".format(
        user(), host(), file, file_dirname, file_basename)
    os.system(command)


def sync_local_folder(source, target):
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    if not os.path.exists(target):
        os.makedirs(target)

    shutil.copytree(source, target, dirs_exist_ok=True)


def sync_local_file(source, target):
    print("Local: {} -> {}".format(source, target))

    # create folder if necessary
    target_dirname = os.path.dirname(target)
    if not os.path.exists(target_dirname):
        os.makedirs(target_dirname)

    shutil.copyfile(source, target)


# ------------------------------------------------------------------------------
# Main execution
# ------------------------------------------------------------------------------
print("Remote: {}@{}".format(user(), host()))

# remove synced files
shutil.rmtree("dotfiles")

# sync remote
sync_remote("scripts/alias.sh")
sync_remote(".vimrc")
sync_remote(".config/helix/config.toml")
sync_remote(".config/helix/languages.toml")

# sync local
sync_local_file(appdata() + "/Code/User/keybindings.json", "dotfiles/vscode/keybindings.json")
sync_local_file(appdata() + "/Code/User/settings.json", "dotfiles/vscode/settings.json")

# remote to local
sync_local_folder("dotfiles/.config/helix", appdata() + "/helix")

# remove temp files created
os.remove("out")
