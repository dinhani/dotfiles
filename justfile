# Show available tasks
default:
    just --list --unsorted

# Backup dotfiles
backup:
    python dotfiles.py backup

# Restore dotfiles
restore:
    python dotfiles.py restore

# Lint and format code
lint:
    yapf -i dotfiles.py