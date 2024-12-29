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
mkdir -p ~/downloads
mkdir -p ~/projects
mkdir -p ~/scripts

# ------------------------------------------------------------------------------
# Install config
# ------------------------------------------------------------------------------
log "Configuring aliases"
cp alias.sh ~/scripts

log "Configuring profiles scripts"

cat << EOF > ~/.bash_profile
source ~/.bashrc
EOF

cat << EOF > ~/.bashrc

# terminal
export HISTSIZE=100000
export HISTFILESIZE=100000
export EDITOR=hx
export VISUAL=hx
export PS1="\w "
source \$HOME/scripts/alias.sh

# system
ulimit -n 65365

# ssh
pkill ssh-agent
eval "\$(ssh-agent -s)"
ssh-add \$HOME/.ssh/dinhani

# windows
export APPDATA=/mnt/c/Users/Renato/AppData/Roaming/
export LOCALAPPDATA=/mnt/c/Users/Renato/AppData/Local/

# homebrew
export PATH=\$PATH:$(brew_bin)
export LDFLAGS="-L$(brew_lib)"
export CPPFLAGS="-L$(brew_include)"

# asdf
source $(brew_opt)/asdf/libexec/asdf.sh

# native languages
source \$HOME/.cargo/env

# other tools
export PATH=\$PATH:/usr/local/FlameGraph
eval "\$(zoxide init bash)"
EOF

# ------------------------------------------------------------------------------
# Config editor
# ------------------------------------------------------------------------------
log "Configuring editor"
sudo update-alternatives --install /usr/bin/editor editor "$(brew_bin)/hx" 100

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
# Config home and user
# ------------------------------------------------------------------------------
log "Configuring Git"
git config --global user.email "$EMAIL"
git config --global user.name "Renato Dinhani"

# ------------------------------------------------------------------------------
# Install APT basic tools
# ------------------------------------------------------------------------------
if is_linux; then
    log "Updating APT"
    sudo apt update

    log "Installing APT build tools"
    apt_install build-essential
    apt_install curl
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

brew_install autoconf
brew_install bison
brew_install cmake
brew_install gcc
brew_install gcc@11
brew_install gcc@12
brew_install gcc@13
brew_install gcc@14
brew_install gettext
brew_install llvm
brew_install make
brew_install re2c

# ------------------------------------------------------------------------------
# Install CLI tools
# ------------------------------------------------------------------------------
log "Installing CLI tools"

brew_install asdf
brew_install bat
brew_install dasel
brew_install erdtree
brew_install eza
brew_install fd
brew_install fzf
brew_install gitql
brew_install graphviz
brew_install helix
brew_install htmlq
brew_install htop
brew_install imagemagick
brew_install jq
brew_install just
brew_install killport
brew_install lazydocker
brew_install lazygit
brew_install mise
brew_install pandoc
brew_install ripgrep
brew_install rust
brew_install sd
brew_install speedtest-cli
brew_install subversion
brew_install sysstat
brew_install unzip
brew_install util-linux
brew_install w3m
brew_install websocat
brew_install zoxide

# ------------------------------------------------------------------------------
# Install languages / build tools
# ------------------------------------------------------------------------------
brew tap oven-sh/bun

brew_install bazelisk
brew_install bun
brew_install clojure
brew_install crystal
brew_install dmd
brew_install dotnet
brew_install elixir
brew_install erlang
brew_install gleam
brew_install go@1.23
brew_install gradle
brew_install groovy
brew_install haskell-stack
brew_install julia
brew_install kotlin
brew_install leiningen
brew_install lua
brew_install maven
brew_install node@22
brew_install ocaml
brew_install odin
brew_install openjdk@23
brew_install perl
brew_install powershell
brew_install protobuf
brew_install python@3.13
brew_install r
brew_install racket
brew_install rakudo
brew_install ruby@3.4
brew_install rustup
brew_install scala
brew_install solidity
brew_install vlang
brew_install zig

# ------------------------------------------------------------------------------
# Install languages extensions
# ------------------------------------------------------------------------------

# Golang
log "Installing Golang extensions"
go install github.com/go-delve/delve/cmd/dlv@latest
go install github.com/nametake/golangci-lint-langserver@latest
go install golang.org/x/tools/gopls@latest

# Python
log "Installing Python extensions and tools"
pip3 install --break-system-packages bs4 dpath httpie lxml matplotlib mycli networkx numpy pandas polars pgcli python-lsp-server requests ruff scipy selenium unidecode toml tomli yamale yapf

# Ruby
log "Installing Ruby extensions and tools"
gem install --conservative activesupport eth pry nokogiri pp puma rails rufo sinatra solargraph webrick tomlrb tomlib

# ------------------------------------------------------------------------------
# Install pre-compiled tools
# ------------------------------------------------------------------------------
if not_installed "flamegraph.pl"; then
    log "Installing FlameGraph"
    sudo git clone https://github.com/dinhani/FlameGraph-RustTheme /usr/local/FlameGraph
fi

if not_installed "plantuml.jar"; then
    log "Installing PlantUML"
    download https://github.com/plantuml/plantuml/releases/download/v1.2024.6/plantuml-mit-1.2024.6.jar plantuml.jar
    sudo cp $DOWNLOADS/plantuml.jar /usr/local/bin/plantuml.jar
fi

if not_installed "tsv-pretty"; then
    log "Installing tsv-utils"
    download https://github.com/eBay/tsv-utils/releases/download/v2.2.0/tsv-utils-v2.2.0_linux-x86_64_ldc2.tar.gz tsv-utils.tar.gz

    mkdir -p $DOWNLOADS/tsv-utils
    tar -xzvf $DOWNLOADS/tsv-utils.tar.gz -C $DOWNLOADS/tsv-utils --strip-components=2

    sudo mv $DOWNLOADS/tsv-utils/* /usr/local/bin/
    rm -rf $DOWNLOADS/tsv-utils
fi

# ------------------------------------------------------------------------------
# Upgrade software
# ------------------------------------------------------------------------------
if is_linux; then
    log "Upgrading APT software"
    sudo apt upgrade -y
fi

# ------------------------------------------------------------------------------
# TODO: review necessary Rust extensions
# ------------------------------------------------------------------------------

# # Rust
# log "Installing Rust extensions and tools"
# rustup component add clippy
# rustup component add rustfmt
# rustup component add rust-analyzer
# rustup target add wasm32-unknown-unknown

# rustup install nightly-x86_64-unknown-linux-gnu
# rustup target add wasm32-unknown-unknown --toolchain nightly-x86_64-unknown-linux-gnu

# rustup install nightly-2023-03-25-x86_64-unknown-linux-gnu
# rustup target add wasm32-unknown-unknown --toolchain nightly-2023-03-25-x86_64-unknown-linux-gnu

# cargo install cargo-expand
# cargo install cargo-outdated
# cargo install ethabi-cli
# cargo install sqlx-cli
# cargo install wait-service
# cargo install watchexec

# ------------------------------------------------------------------------------
# TODO: Review VSCode extensions process
# ------------------------------------------------------------------------------
# log "Installing VSCode extensions"
# source $(dirname $0)/setup-vscode.sh

# ------------------------------------------------------------------------------
# Install local compiled tools
# ------------------------------------------------------------------------------
# if is_linux; then
#     if [ ! -d "$DOWNLOADS/$DOWNLOADS/WSL2-Linux-Kernel" ]; then
#         log "Cloning WSL2 source"
#         git clone https://github.com/microsoft/WSL2-Linux-Kernel $DOWNLOADS/WSL2-Linux-Kernel
#     fi
# fi

# heaptrack
# if not_installed "heaptrack"; then
#     log "Installing heaptrack"
#     git clone "https://github.com/KDE/heaptrack" $DOWNLOADS/heaptrack

#     cd $DOWNLOADS/heaptrack
#     cmake -DCMAKE_BUILD_TYPE=Release
#     make -j16
#     sudo cp -r $DOWNLOADS/heaptrack/bin/* /usr/local/bin
#     sudo cp -r $DOWNLOADS/heaptrack/lib/* /usr/local/lib

#     cd
# fi

# perf
# if is_linux && not_installed "perf"; then
#     log "Installing perf"

#     cd $DOWNLOADS/WSL2-Linux-Kernel/tools/perf
#     NO_LIBTRACEEVENT=1 make -j16
#     sudo cp perf /usr/local/bin/perf

#     cd
# fi

# pikchr
# if not_installed "pikchr"; then
#     log "Installing pikchr"

#     git clone https://github.com/drhsqlite/pikchr.git $DOWNLOADS/pikchr
#     cd $DOWNLOADS/pikchr
#     make
#     sudo cp pikchr /usr/local/bin

#     cd
# fi

# valgrind
# if not_installed "valgrind"; then
#     log "Installing valgrind"
#     git clone https://sourceware.org/git/valgrind.git $DOWNLOADS/valgrind

#     cd $DOWNLOADS/valgrind
#     ./autogen.sh
#     ./configure
#     make -j16
#     sudo make install

#     cd
# fi
