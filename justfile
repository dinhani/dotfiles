set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

# Show available tasks
[group("project")]
default:
    just --list --unsorted

# Lint and format code
[group("project")]
lint:
    yapf -i dotfiles.py

# Backup or restore dotfiles (interactive selection)
[group("dotfiles")]
dotfiles:
    python dotfiles.py
alias dot := dotfiles

# Setup a Linux or MacOs system from scratch
[group("system")]
setup email="renatodinhani@gmail.com":
    EMAIL={{email}} ./setup-unix.sh
