# Show available tasks
default:
    just --list --unsorted

# Backup dotfiles
backup:
    python bin-dotfiles.py backup

# Restore dotfiles
restore:
    python bin-dotfiles.py restore

# Server that receives remote dotfiles
server:
    ruby bin-server.rb

# Lint and format code
lint:
    yapf -i bin-dotfiles.py