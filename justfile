set windows-shell := ["pwsh.exe", "-NoLogo", "-NoProfile", "-Command"]

[doc("List recipes")]
[group("project")]
default:
    @just --list --unsorted

[doc("Format Python code")]
[group("project")]
lint:
    yapf -i dotfiles.py dotfiles_tui.py

[doc("Backup or restore dotfiles")]
[group("run")]
dotfiles:
    python dotfiles.py
alias dot := dotfiles

[doc("Setup Linux or macOS")]
[group("run")]
setup email="renatodinhani@gmail.com":
    EMAIL={{email}} ./setup-unix.sh
