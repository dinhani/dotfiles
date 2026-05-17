# Show available tasks
[group("project")]
default:
    just --list --unsorted

# Lint and format code
[group("project")]
lint:
    yapf -i dotfiles.py

# Backup dotfiles
[group("dotfiles")]
backup:
    python3 dotfiles.py backup

# Restore dotfiles
[group("dotfiles")]
restore:
    python3 dotfiles.py restore

# Setup a Linux or MacOs system from scratch
[group("system")]
setup email="renatodinhani@gmail.com":
    EMAIL={{email}} ./setup-unix.sh
