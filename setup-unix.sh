#!/bin/bash
source $(dirname $0)/setup-unix-functions.sh

# ------------------------------------------------------------------------------
# Parse input parameters
# ------------------------------------------------------------------------------
if [ -z "$EMAIL" ]; then
    echo "Error: EMAIL is not set. Aborting script."
    exit 1
fi

# ------------------------------------------------------------------------------
# Install dirs
# ------------------------------------------------------------------------------
log "Creating directories"
mkdir -p $DIR_DOWNLOADS
mkdir -p $DIR_SCRIPTS
mkdir -p $DIR_TOOLS

# ------------------------------------------------------------------------------
# Install config
# ------------------------------------------------------------------------------
log "Configuring aliases"
cp scripts/alias.sh $DIR_SCRIPTS

# ------------------------------------------------------------------------------
# Install .shell_common
# ------------------------------------------------------------------------------
log "Configuring common shell setup"

cat << EOF > ~/.shell_common
# aliases
source $DIR_SCRIPTS/alias.sh

# terminal
export HISTSIZE=100000
export HISTFILESIZE=100000
export EDITOR=hx
export VISUAL=hx

# windows
export APPDATA=/mnt/c/Users/Renato/AppData/Roaming/
export LOCALAPPDATA=/mnt/c/Users/Renato/AppData/Local/

# homebrew
export PATH=$(brew_dir)/bin:\$PATH
export PATH=$(brew_dir)/sbin:\$PATH
export CMAKE_LIBRARY_PATH=$(brew_dir)/lib
export CMAKE_SYSTEM_LIBRARY_PATH=$(brew_dir)/lib
export CPATH=$(brew_dir)/include
export LD_LIBRARY_PATH=$(brew_dir)/lib
export LIBRARY_PATH=$(brew_dir)/lib
export PKG_CONFIG_PATH=$(brew_dir)/lib/pkgconfig

# langs
export PATH=\$PATH:$HOME/go/bin
export PATH=\$PATH:$HOME/.cargo/bin

# custom tools
export PATH=\$PATH:$DIR_TOOLS
export PATH=\$PATH:$DIR_TOOLS/FlameGraph

# system
ulimit -n 65365

# ssh
pkill ssh-agent
eval "\$(ssh-agent -s)"
ssh-add $HOME/.ssh/dinhani

# asdf
source $(brew_dir)/opt/asdf/libexec/asdf.sh

# rust
source $HOME/.cargo/env
EOF

# ------------------------------------------------------------------------------
# Install .bashrc
# ------------------------------------------------------------------------------
log "Configuring .bash_profile"
cat << EOF > ~/.bash_profile
source ~/.bashrc
EOF

log "Configuring .bashrc"
cat << EOF > ~/.bashrc
# common
source ~/.shell_common

# completions
for COMPLETION in "$(brew_dir)/etc/bash_completion.d/"*
do
    source "\${COMPLETION}"
done

# starship
eval "\$(starship init bash)"

# zoxide
eval "\$(zoxide init bash)"
EOF

reload

# ------------------------------------------------------------------------------
# Install .zshrc / Oh My ZSH
# ------------------------------------------------------------------------------

log "Configuring .zshrc"
cat << EOF > ~/.zshrc
# common
source ~/.shell_common

# oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
source $HOME/.oh-my-zsh/oh-my-zsh.sh

# ls colors
export LS_COLORS="$LS_COLORS:ow=1;34:tw=1;34:"
zstyle ':completion:*' list-colors \${(s.:.)LS_COLORS}

# starship
eval "\$(starship init zsh)"

# zoxide
eval "\$(zoxide init bash)"
EOF

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My ZSH"
    CHSH=no KEEP_ZSHRC=no RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

reload

# ------------------------------------------------------------------------------
# Install APT basic tools
# ------------------------------------------------------------------------------
if is_linux; then
    log "Updating APT repositories"
    sudo apt update

    log "Upgrading APT software"
    sudo apt upgrade -y

    log "Installing APT build tools"
    install_apt build-essential
    install_apt curl
fi

# ------------------------------------------------------------------------------
# Install Homebrew
# ------------------------------------------------------------------------------
if not_installed "brew"; then
    log "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    reload
fi

# ------------------------------------------------------------------------------
# Install build tools
# ------------------------------------------------------------------------------
log "Installing build tools"

install_brew autoconf
install_brew bison
install_brew cmake
install_brew flex
install_brew gcc
install_brew gcc@11
install_brew gcc@12
install_brew gcc@13
install_brew gettext
install_brew just
install_brew llvm
install_brew make
install_brew re2c

# ------------------------------------------------------------------------------
# Install CLI tools
# ------------------------------------------------------------------------------
log "Installing CLI tools"

# shells
install_brew bash
install_brew nushell
install_brew zsh
install_brew starship

# managers
install_brew asdf
install_brew mise

# other
install_brew bat
install_brew dasel
install_brew erdtree
install_brew eza
install_brew fd
install_brew fzf
install_brew gitql
install_brew gnupg
install_brew graphviz
install_brew helix
install_brew htmlq
install_brew htop
install_brew imagemagick
install_brew jq
install_brew killport
install_brew lazydocker
install_brew lazygit
install_brew pandoc
install_brew ripgrep
install_brew sd
install_brew speedtest-cli
install_brew subversion
install_brew unzip
install_brew util-linux
install_brew w3m
install_brew websocat
install_brew zoxide

# linux specific
if is_linux; then
    install_apt heaptrack
    install_apt heaptrack-gui
    install_brew sysstat
    install_brew valgrind
fi

# mac specific
if is_mac; then
    install_brew podman
    ln -sfn $(brew_dir)/bin/podman $(brew_dir)/bin/docker
fi

# ------------------------------------------------------------------------------
# Install languages / build tools
# ------------------------------------------------------------------------------
brew tap oven-sh/bun

install_brew bazelisk
install_brew bun
install_brew clojure
install_brew crystal
install_brew dmd
install_brew dotnet
install_brew dub
install_brew elixir
install_brew erlang
install_brew gleam
install_brew go
install_brew gradle
install_brew groovy
install_brew haskell-stack
install_brew julia
install_brew kotlin
install_brew leiningen
install_brew lua
install_brew maven
install_brew node@22
install_brew ocaml
install_brew odin
install_brew openjdk
install_brew perl
install_brew powershell
install_brew protobuf
install_brew python
install_brew r
install_brew racket
install_brew rakudo
install_brew ruby
install_brew scala
install_brew solidity
install_brew vlang
install_brew zig

if not_installed "rustup"; then
    log "Installing rustup"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

# ------------------------------------------------------------------------------
# Install languages extensions
# ------------------------------------------------------------------------------

# Golang
log "Installing Golang extensions"
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
go install github.com/nametake/golangci-lint-langserver@latest
go install golang.org/x/tools/gopls@latest

# Python
log "Installing Python extensions and tools"
pip3 install --break-system-packages bs4 dpath httpie lxml matplotlib mycli networkx numpy pandas polars pgcli python-lsp-server requests ruff scipy selenium unidecode toml tomli yamale yapf

# Ruby
log "Installing Ruby extensions and tools"
gem install --conservative activesupport eth pry nokogiri pp puma rails rufo sinatra solargraph webrick tomlrb tomlib

# Rust
log "Installing Rust toolchains"
rustup toolchain install stable
rustup toolchain install nightly

rustup component add clippy
rustup component add rustfmt
rustup component add rust-analyzer
rustup +nightly component add clippy
rustup +nightly component add rustfmt
rustup +nightly component add rust-analyzer

log "Installing Rust extensions"
cargo install cargo-expand
cargo install wait-service

# ------------------------------------------------------------------------------
# Install VSCode extensions
# ------------------------------------------------------------------------------
# General

# WSL / SSH
install_vscode ms-vscode-remote.remote-wsl         # WSL
install_vscode ms-vscode-remote.remote-ssh         # SSH

# General
install_vscode github.copilot                      # Copilot
install_vscode dinhani.divider                     # Divider
install_vscode vscode-icons-team.vscode-icons      # Icons
install_vscode oderwat.indent-rainbow              # Indent Rainbow
install_vscode danbackes.lines                     # Lines

# Language / tools
install_vscode EditorConfig.EditorConfig           # .editorconfig
install_vscode mechatroner.rainbow-csv             # CSV
install_vscode golang.Go                           # Go
install_vscode ZainChen.json                       # JSON
install_vscode yzhang.markdown-all-in-one          # Markdown
install_vscode ms-vscode.PowerShell                # PowerShell
install_vscode rust-lang.rust-analyzer             # Rust
install_vscode tamasfe.even-better-toml            # TOML

# ------------------------------------------------------------------------------
# Install pre-compiled tools
# ------------------------------------------------------------------------------
if not_installed "flamegraph.pl"; then
    log "Installing FlameGraph"

    rm -rf $DIR_DOWNLOADS/FlameGraph
    git clone https://github.com/dinhani/FlameGraph-RustTheme $DIR_DOWNLOADS/FlameGraph
    cp -rf $DIR_DOWNLOADS/FlameGraph $DIR_TOOLS
fi

if not_installed "plantuml.jar"; then
    log "Installing PlantUML"

    rm $DIR_DOWNLOADS/plantuml.jar
    download https://github.com/plantuml/plantuml/releases/download/v1.2024.6/plantuml-mit-1.2024.6.jar plantuml.jar
    cp $DIR_DOWNLOADS/plantuml.jar $DIR_TOOLS/plantuml.jar
fi

if not_installed "tsv-pretty"; then
    log "Installing tsv-utils"

    rm $DIR_DOWNLOADS/tsv-utils.tar.gz
    rm -rf $DIR_DOWNLOADS/tsv-utils
    download https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz tsv-utils.tar.gz

    mkdir -p $DIR_DOWNLOADS/tsv-utils
    tar -xzvf $DIR_DOWNLOADS/tsv-utils.tar.gz -C $DIR_DOWNLOADS/tsv-utils --strip-components=2

    mv $DIR_DOWNLOADS/tsv-utils/* $DIR_TOOLS
    rm -rf $DIR_DOWNLOADS/tsv-utils
fi

# ------------------------------------------------------------------------------
# Config editor
# ------------------------------------------------------------------------------
if is_linux; then
    log "Configuring editor"
    sudo update-alternatives --install /usr/bin/editor editor "$(brew_dir)/bin/hx" 100
fi

# ------------------------------------------------------------------------------
# Config GPG key
# ------------------------------------------------------------------------------
if [ ! -e ~/.gnupg/pubring.kbx ]; then
    log "Configuring GPG key"
gpg --batch --gen-key <<EOF
    Key-Type: 1
    Key-Length: 4096
    Subkey-Type: 1
    Subkey-Length: 4096
    Name-Real: Renato Dinhani
    Name-Email: $EMAIL
    Expire-Date: 0
    %no-protection
EOF
fi

# ------------------------------------------------------------------------------
# Config SSH key
# ------------------------------------------------------------------------------
if [ ! -e ~/.ssh/dinhani.pub ]; then
    log "Configuring SSH key"
    ssh-keygen -t ed25519 -C "$EMAIL" -N "" -f ~/.ssh/dinhani
fi

# ------------------------------------------------------------------------------
# Config Git
# ------------------------------------------------------------------------------
log "Configuring Git"
git config --global user.email "$EMAIL"
git config --global user.name "Renato Dinhani"

# ------------------------------------------------------------------------------
# Install Desktop tools
# ------------------------------------------------------------------------------
if is_mac; then
    # hardware
    install_brew elgato-stream-deck
    install_brew logitech-g-hub
    install_brew linearmouse

    # media
    install_brew spotify

    # terminal    
    install_brew ghostty

    # editors
    install_brew intellij-idea
    install_brew rstudio
    install_brew visual-studio-code    

    # dev stuff
    install_brew bruno
    install_brew devtoys
    install_brew github
    install_brew notable    

    # work / utils
    install_brew google-chrome
    install_brew slack
fi

# ------------------------------------------------------------------------------
# Install local compiled tools
# ------------------------------------------------------------------------------

# wsl2 source checkout
if is_linux && [ ! -d "$DIR_DOWNLOADS/WSL2-Linux-Kernel" ]; then
    log "Cloning WSL2 source"
    git clone https://github.com/microsoft/WSL2-Linux-Kernel $DIR_DOWNLOADS/WSL2-Linux-Kernel
fi

# perf
if is_linux && not_installed "perf"; then
    log "Installing perf"

    cd $DIR_DOWNLOADS/WSL2-Linux-Kernel/tools/perf
    NO_LIBTRACEEVENT=1 make -j16
    cp perf $DIR_TOOLS

    cd
fi

# pikchr
if not_installed "pikchr"; then
    log "Installing pikchr"

    git clone https://github.com/drhsqlite/pikchr.git $DIR_DOWNLOADS/pikchr
    cd $DIR_DOWNLOADS/pikchr
    make
    cp pikchr $DIR_TOOLS

    cd
fi
