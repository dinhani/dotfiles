# Git aliases

function ggam    { git add --all .; git commit -m }
function gga     { git add --all }
function ggb     { git branch }
function ggbkill { git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {} }
function ggc     { git checkout }
function ggd     { git diff $1 | bat }
function ggdn    { git diff --name-only }
function ggl     { git log | bat }
function ggm     { param ($message) git commit -m $message }
function ggma    { git commit --amend -m }
function ggman   { git commit --amend --no-edit }
function ggme    { param ($message) git commit --allow-empty -m $message }
function ggp     { git pull }
function ggr     { git reset }
function ggrb    { git rebase -i }
function ggs     { git status }
function ggsub   { git submodule update --init --recursive }
