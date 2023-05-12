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

def sync(file):
    print("Sync: {}".format(file))

    # create folder if necessary
    file_dirname = "dotfiles/" + os.path.dirname(file)
    file_basename = os.path.basename(file)
    if file_dirname != "" and not os.path.exists(file_dirname):
        os.makedirs(file_dirname)

    # execute sync command
    command = "scp {}@{}:~/{} {}/{} > out".format(user(), host(), file, file_dirname, file_basename)
    os.system(command)

# ------------------------------------------------------------------------------
# Main execution
# ------------------------------------------------------------------------------
print("Remote: {}@{}".format(user(), host()))

# remove synced files
shutil.rmtree("dotfiles")

# sync files
sync("scripts/alias.sh")
sync(".vimrc")
sync(".config/helix/config.toml")
sync(".config/helix/languages.toml")

# remove temp files created
os.remove("out")