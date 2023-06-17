# checks
is_linux() { [[ "$(uname -s)" == "Linux" ]]; }
is_mac() { [[ "$(uname -s)" == "Darwin" ]]; }

# folders
alias cdp="cd ~/Desktop/projects"

# docker
alias dkill="docker ps | awk '{if (NR > 1) {print \$1}}' | xargs -I{} docker kill {}"
alias dclean="docker container prune -f; docker image ls | grep none | awk '{print \$3}' | xargs docker image rm; docker image prune -f; docker network prune -f"

# docker-compose
alias dc="docker-compose"

# du
if is_mac; then
  alias du=gdu
fi
function duh() {
  du -h --exclude=/mnt/* $1 | sort -rh | head -n 20
}

# fd
alias fd="fd --exclude .git --exclude target --color=never --hidden"

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
alias gb="git branch"
alias gbkill="git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {}"
alias gc="git checkout"
alias gd="git diff | bat"
alias gl="git log | bat"
alias gm="git commit -m"
alias gma="git commit --amend -m"
alias gp="git pull"
alias gr="git reset"
alias grb="git rebase -i"
alias gs="git status"

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

# markdown
function md() {
  pandoc $1 | w3m -T text/html
}
alias mdr="md README.md"
alias mdc="md CONTRIBUTING.md"

# rg
alias rgc="rg -B 1 -A 1"i

# timeout
if is_mac; then
  alias timeout=gtimeout
fi