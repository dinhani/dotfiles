# Git aliases

function ggam    { git add --all .; git commit -m @args }           # Stages everything and commits with a message.
function gga     { git add --all @args }                            # Stages everything.
function ggb     { git branch @args }                               # Lists branches.
function ggc     { git checkout @args }                             # Checks out.
function ggd     { git diff @args | bat }                           # Shows the diff in bat.
function ggdn    { git diff --name-only @args }                     # Lists changed file names.
function ggl     { git log @args | bat }                            # Shows the log in bat.
function ggm     { git commit -m @args }                            # Commits with a message.
function ggma    { git commit --amend -m @args }                    # Amends the last commit message.
function ggman   { git commit --amend --no-edit @args }             # Amends the last commit, keeping its message.
function ggme    { git commit --allow-empty -m @args }              # Creates an empty commit with a message.
function ggp     { git pull @args }                                 # Pulls.
function ggr     { git reset @args }                                # Resets.
function ggrb    { git rebase -i @args }                            # Starts an interactive rebase.
function ggs     { git status @args }                               # Shows status.
function ggsub   { git submodule update --init --recursive @args }  # Initializes and updates submodules recursively.

# Deletes local branches except main, master and the current one, asking for each.
function ggbkill {
    $branchCurrent = git branch --show-current
    git branch --format='%(refname:short)' |
        Where-Object { $_ -notin 'main', 'master', $branchCurrent } |
        ForEach-Object {
            if ((Read-Host "Delete $_? [y/N]") -eq 'y') {
                git branch -D $_
            }
        }
}
