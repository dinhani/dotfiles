# folders
alias cdp="cd ~/Desktop/projects"

# docker
alias dkill="docker ps | awk '{if (NR > 1) {print \$1}}' | xargs -I{} docker kill {}"
alias dclean="docker container prune -f; docker image ls | grep none | awk '{print \$3}' | xargs docker image rm; docker image prune -f; docker network prune -f"

# docker-compose
alias dc="docker-compose"

# git
alias ga="git add --all"
alias gb="git branch"
alias gbkill="git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {}"
alias gc="git checkout"
alias gd="git diff"
alias gl="git log | bat"
alias gm="git commit -m"
alias gp="git pull"
alias gr="git reset"
alias grb="git rebase -i"
alias gs="git status"

# helix
alias xh="hx"

# kubernetes
alias k="kubectl"

# markdown
function md() {
  pandoc $1 | w3m -T text/html
}
alias mdr="md README.md"
alias mdc="md CONTRIBUTING.md"