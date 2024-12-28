# Show available tasks
default:
    just --list --unsorted

# Backup dotfiles
backup:
    python dotfiles.py backup

# Restore dotfiles
restore:
    python dotfiles.py restore

# Setup a Linux or MacOs system from scratch
setup email="renatodinhani@gmail.com":
    EMAIL={{email}} ./setup-unix.sh

# Lint and format code
lint:
    yapf -i dotfiles.py
