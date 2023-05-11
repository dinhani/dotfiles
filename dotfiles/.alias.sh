# docker
alias dkill="docker ps | awk '{if (NR > 1) {print \$1}}' | xargs -I{} docker kill {}"
alias dclean="docker container prune -f; docker image ls | grep none | awk '{print \$3}' | xargs docker image rm; docker image prune -f; docker network prune -f"

# git
alias gb="git branch"
alias gbkill="git branch | grep -vE 'main|master' | xargs -p -I{} git branch -D {}"
alias gc="git checkout"
alias gs="git status"

# kubernetes
alias k="kubectl"