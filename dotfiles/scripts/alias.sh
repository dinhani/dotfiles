# checks
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

# chezmoi
alias cz="chezmoi"

# docker
alias dkill="docker ps --format '{{.ID}}' | xargs -I{} docker kill {}"
alias dclean="docker container prune -f; docker network prune -f; docker volume prune -f; docker image ls | grep none | awk '{print \$3}' | xargs docker image rm; docker image prune -f;"

# docker-compose
alias dc="docker-compose"

# du
if is_mac; then
  alias du=gdu
fi
function duh() {
  du -xh $1 | sort -rh | head -n 40
}
function duhf() {
  search_path=$1
  if [ -z "$search_path" ]; then
    search_path=.
  fi
  fd --search-path $search_path --exclude /mnt --type file --exec du -hx | sort -rh | head -n 40
}

# fd
alias fd="fd --exclude .git --exclude target --exclude /mnt --color=never --hidden"

# fzf
function cdf() {
  dir=$(fd --type directory --exclude .git --exclude target | fzf)
  if [ -n "$dir" ]; then
    cd $dir
  fi
}
function lsf() {
  file=$(fd --type file --exclude .git --exclude target | fzf --preview "bat --style=numbers --color=always {}")
  if [ -n "$file" ]; then
    echo $file
  fi
}

# git
alias ga="git add --all"
alias gam="git add --all .; git commit -m"
alias gb="git branch"
alias gbkill="git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {}"
alias gc="git checkout"
function gd() {
  git diff $1 | bat
}
alias gdn="git diff --name-only"
alias gl="git log | bat"
alias gm="git commit -m"
alias gma="git commit --amend -m"
alias gman="git commit --amend --no-edit"
alias gp="git pull"
alias gr="git reset"
alias grb="git rebase -i"
alias gs="git status"
alias gsub="git submodule update --init --recursive"

# helix
alias xh="hx"

# history
function h() {   
  if is_mac; then
    command=$(history 0 | awk ' {$1=""; print substr($0, 2) }' | sort | uniq | fzf --tac)
  fi
  if is_linux; then
    command=$(history | awk ' {$1=""; print substr($0, 2) }' | sort | uniq | fzf --tac)
  fi
  echo $command
  eval $command
}

# kubernetes
alias k="kubectl"
alias kn="kubens"

function kauth() {
  gcloud container clusters get-credentials $1 --region $2
}

function kc() {
  k exec --stdin --tty $1 -- /bin/bash
}

# markdown
function md() {
  pandoc $1 | w3m -T text/html
}
alias mdr="md README.md"
alias mdc="md CONTRIBUTING.md"

# perf
alias prec="perf record --call-graph dwarf -F 1000 -g"
alias pflame="perf script | stackcollapse-perf.pl | flamegraph.pl  > flame.svg"

# rg
alias rgc="rg -B 1 -A 1 --line-number --context-separator ''"

# server
alias serve="xdg-open http://127.0.0.1:8000; python -m http.server"

# solc
alias sc="solc --base-path . --include-path ./node_modules --include-path ../node_modules"

# timeout
if is_mac; then
  alias timeout=gtimeout
fi

# tree
alias tree="~/.cargo/bin/erd -s name --dir-order first -y inverted --disk-usage logical -H"

# wget
alias wget-mirror="wget --mirror --convert-links --adjust-extension --page-requisites --no-parent --no-clobber"
