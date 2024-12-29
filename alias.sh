# checks
function is_linux() { [[ "$(uname -s)" == "Linux"  ]]; }
function is_mac()   { [[ "$(uname -s)" == "Darwin" ]]; }
function is_bash()  { [[ -n "$BASH_VERSION" ]]; }
function is_zsh()   { [[ -n "$ZSH_VERSION"  ]]; }

# self
# edit-alias
alias a="hx ~/scripts/alias.sh" # edit-alias

# edit-init
if is_bash; then
  alias i="hx ~/.bashrc"
fi
if is_zsh; then
  alias i="hx ~/.zshrc"
fi

# source init
if is_bash; then
  alias s="echo 'Reloading .bashrc...'; source ~/.bashrc;"
fi
if is_zsh; then
  alias s="echo 'Reloading .zshrc...'; source ~/.zshrc"
fi

# clear
alias c="clear"

# docker
alias dip="ifconfig eth0 | rg inet"
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
alias fd1="fd . --max-depth 1"
alias fd2="fd . --max-depth 2"

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
alias gme="git commit --allow-empty -m"
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
  history -s $command
  eval $command
}

# httpie
alias http="http --unsorted --verbose --all"
function rpc() {
  url=$1
  method=$2
  args=""
  for arg in "${@:3}"
  do
    # if valid json, use json assignment, otherwise use string assignment
    echo $arg | jq -e "type" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      args+="params[]:=$arg "
    else
      args+="params[]=$arg "
    fi
  done

  command="http $url jsonrpc=2.0 id=$(date +%s%N) method=$method $args --sorted"
  echo $command
  eval $command
}

# linter
function lint() {
  if [ -f Cargo.toml ]; then
    cargo +nightly fmt --all
    cargo clippy --all-targets
  fi
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

function mv-ascii() {
  while read filename; do
    dir=$(dirname "$filename")
    source=$(basename "$filename")
    target=$(echo $source | iconv -f utf-8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr '_' '-' | sed 's/---/-/')

    # ignore special cases
    if [[ "$source" == Cargo.* ]]; then
      continue
    fi

    # rename only if name changed
    if [[ $source != $target ]]; then
      mv "$dir/$source" "$dir/__$target" # workaround: only changing case fails in Windows, so we create a temporary version with __ prefix before renaming to the final version
      mv "$dir/__$target" "$dir/$target"
    fi
  done
}

# perf
alias prec="perf record --call-graph dwarf -F 1000 -g"
alias pflame="perf script | stackcollapse-perf.pl | flamegraph.pl --width 1900 --height 24 --fonttype 'Jetbrains Mono' --nametype '' --color rust --bgcolors grey --hash > flame.svg"

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

# watch
alias bwatch="browser-sync . --watch" # browser-watch
alias fwatch="watchexec --poll 500ms --restart" # file-watch

# wget
alias wget-mirror="wget --mirror --convert-links --adjust-extension --page-requisites --no-parent --no-clobber"
