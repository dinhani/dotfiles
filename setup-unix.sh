#!/bin/bash
source $(dirname $0)/setup-unix-functions.sh

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
EMAIL=renatodinhani@gmail.com
log "Using e-mail: $EMAIL"

# ------------------------------------------------------------------------------
# Install dirs
# ------------------------------------------------------------------------------
log "Creating directories"
mkdir -p ~/downloads
mkdir -p ~/projects

# ------------------------------------------------------------------------------
# Install config
# ------------------------------------------------------------------------------
log "Configuring .bash_profile and .bashrc"

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

# windows
export APPDATA=/mnt/c/Users/Renato/AppData/Roaming/
export LOCALAPPDATA=/mnt/c/Users/Renato/AppData/Local/

# homebrew
export PATH=\$PATH:$(brew_bin)
source $(brew_opt)/asdf/libexec/asdf.sh

# languages
source \$HOME/.cargo/env

# tools
export PATH=\$PATH:/usr/local/FlameGraph
eval "\$(zoxide init bash)"

# ssh
pkill ssh-agent
eval "\$(ssh-agent -s)"
ssh-add \$HOME/.ssh/dinhani
EOF

# ------------------------------------------------------------------------------

log "Configuring editor"
sudo update-alternatives --set editor hx

# ------------------------------------------------------------------------------
# Install APT repos
# ------------------------------------------------------------------------------
log "Updating repos"
sudo apt update

# ------------------------------------------------------------------------------
# Install APT build tools
# ------------------------------------------------------------------------------
log "Installing build tools"
apt_install autoconf
apt_install bison
apt_install build-essential
apt_install clang
apt_install clangd
apt_install cmake
apt_install docker.io
apt_install extra-cmake-modules
apt_install flex
apt_install gettext
apt_install gfortran
apt_install pkg-config
apt_install re2c
apt_install scdoc

log "Installing build libraries"
apt_install libbabeltrace-dev
apt_install libboost-all-dev
apt_install libbz2-dev
apt_install libcap-dev
apt_install libclang-dev
apt_install libcurl4-openssl-dev
apt_install libdwarf-dev
apt_install libelf-dev
apt_install libgd-dev
apt_install libgflags-dev
apt_install libkchart-dev
apt_install libkf5iconthemes-dev
apt_install libkf5kio-dev
apt_install libkf5threadweaver-dev
apt_install liblzma-dev
apt_install libncurses5-dev
apt_install libnuma-dev
apt_install libonig-dev
apt_install libperl-dev
apt_install libpfm4-dev
apt_install libpq-dev
apt_install libpugixml-dev
apt_install libreadline-dev
apt_install librust-atk-dev
apt_install librust-gdk-sys-dev
apt_install libsecp256k1
apt_install libslang2-dev
apt_install libsnappy-dev
apt_install libsoup2.4-dev
apt_install libssl-dev
apt_install libtool
apt_install libudev-dev
apt_install libunwind-dev
apt_install libx11-dev
apt_install libxt-dev
apt_install libyaml-dev
apt_install libzip-dev
apt_install libzstd-dev
apt_install qtbase5-dev
apt_install systemtap-sdt-dev

# ------------------------------------------------------------------------------
# Install homebrew tools
# ------------------------------------------------------------------------------
log "Installing homebrew tools"
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew_install bat
brew_install dasel
brew_install eza
brew_install fd
brew_install ffmpeg
brew_install fzf
brew_install gitql
brew_install graphviz
brew_install helix
brew_install htop
brew_install imagemagick
brew_install jq
brew_install just
brew_install lazydocker
brew_install lazygit
brew_install pandoc
brew_install rename
brew_install rename
brew_install ripgrep
brew_install speedtest-cli
brew_install subversion
brew_install sysstat
brew_install unzip
brew_install w3m
brew_install zoxide

# ------------------------------------------------------------------------------
# Install pre-compiled tools
# ------------------------------------------------------------------------------
if not_installed "asdf"; then
    log "Installing ASDF"
    git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.14.0
fi

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
# Install local compiled tools
# ------------------------------------------------------------------------------
if [ ! -d "$DOWNLOADS/$DOWNLOADS/WSL2-Linux-Kernel" ]; then
    log "Cloning WSL2 source"
    git clone https://github.com/microsoft/WSL2-Linux-Kernel $DOWNLOADS/WSL2-Linux-Kernel
fi

# heaptrack
if not_installed "heaptrack"; then
    log "Installing heaptrack"
    git clone "https://github.com/KDE/heaptrack" $DOWNLOADS/heaptrack

    cd $DOWNLOADS/heaptrack
    cmake -DCMAKE_BUILD_TYPE=Release
    make -j16
    sudo cp -r $DOWNLOADS/heaptrack/bin/* /usr/local/bin
    sudo cp -r $DOWNLOADS/heaptrack/lib/* /usr/local/lib

    cd
fi

# perf
if not_installed "perf"; then
    log "Installing perf"

    cd $DOWNLOADS/WSL2-Linux-Kernel/tools/perf
    NO_LIBTRACEEVENT=1 make -j16
    sudo cp perf /usr/local/bin/perf

    cd
fi

# pikchr
if not_installed "pikchr"; then
    log "Installing pikchr"

    git clone https://github.com/drhsqlite/pikchr.git $DOWNLOADS/pikchr
    cd $DOWNLOADS/pikchr
    make
    sudo cp pikchr /usr/local/bin

    cd
fi

# valgrind
if not_installed "valgrind"; then
    log "Installing valgrind"
    git clone https://sourceware.org/git/valgrind.git $DOWNLOADS/valgrind

    cd $DOWNLOADS/valgrind
    ./autogen.sh
    ./configure
    make -j16
    sudo make install

    cd
fi

# ------------------------------------------------------------------------------
# Install ASDF languages / tools
# ------------------------------------------------------------------------------
log "Installing languages"

asdf plugin add cmake
asdf plugin add dmd    https://github.com/sylph01/asdf-dmd.git
asdf plugin add eza    https://github.com/lwiechec/asdf-eza.git
asdf plugin add gleam
asdf plugin add just   https://github.com/olofvndrhr/asdf-just
asdf plugin add lein   https://github.com/miorimmax/asdf-lein.git
asdf plugin add protoc https://github.com/paxosglobal/asdf-protoc.git
asdf plugin add r      https://github.com/asdf-community/asdf-r.git

echo > ~/.tool-versions
asdf_install  bazel            8.0.0
asdf_install  bun              1.1.42
asdf_install  clojure          1.11.3.1488
asdf_install  crystal          1.14.0
asdf_install  dmd              2.092.1
asdf_install  dotnet           9.0.101
asdf_install  elixir           1.18.0
asdf_install  erlang           26.2.1
asdf_install  gleam            1.6.3
asdf_install  golang           1.23.4
asdf_install  gradle           8.12
asdf_install  groovy           4.0.24
asdf_install  haskell          9.12.1
asdf_install  java             openjdk-21.0.1
asdf_install  julia            1.11.2
asdf_install  kotlin           2.1.0
asdf_install  lein             2.11.2
asdf_install  lua              5.4.6
asdf_install  maven            3.9.6
asdf_install  nodejs           22.0.0
asdf_install  ocaml            5.1.1
asdf_install  odin             dev-2024-05
asdf_install  perl             5.38.2
asdf_install  php              8.3.7
asdf_install  powershell-core  7.4.2
asdf_install  python           3.11.6
asdf_install  r                4.4.0
asdf_install  racket           8.12
asdf_install  raku             2024.04
asdf_install  ruby             3.2.2
asdf_install  scala            3.4.1
asdf_install  solidity         0.8.25
asdf_install  v                weekly.2024.37
asdf_install  yarn             1.22.21
asdf_install  zig              0.13.0

# tools
asdf_install  cmake            3.30.1
asdf_install  eza              0.18.16
asdf_install  protoc           27.2

if not_installed "rustup"; then
    log "Installing Rust"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    reload
fi

# ------------------------------------------------------------------------------
# Install languages extensions
# ------------------------------------------------------------------------------

# Node
log "Installing NodeJS extensions and tools"
npm install -g @mermaid-js/mermaid-cli
npm install -g browser-sync
npm install -g phantomjs-prebuilt
npm install -g tldr

# Python
log "Installing Python extensions and tools"
pip install bs4 dpath httpie lxml matplotlib mycli networkx numpy pandas polars pgcli python-lsp-server requests ruff scipy selenium unidecode toml tomli yamale yapf

# Ruby
log "Installing Ruby extensions and tools"
gem install --conservative activesupport bundler eth pry nokogiri pp puma rails rufo sinatra solargraph webrick tomlrb tomlib

# Rust
log "Installing Rust extensions and tools"
rustup component add clippy
rustup component add rustfmt
rustup component add rust-analyzer
rustup target add wasm32-unknown-unknown

rustup install nightly-x86_64-unknown-linux-gnu
rustup target add wasm32-unknown-unknown --toolchain nightly-x86_64-unknown-linux-gnu

rustup install nightly-2023-03-25-x86_64-unknown-linux-gnu
rustup target add wasm32-unknown-unknown --toolchain nightly-2023-03-25-x86_64-unknown-linux-gnu

cargo install cargo-expand
cargo install cargo-outdated
cargo install erdtree
cargo install ethabi-cli
cargo install htmlq
cargo install killport
cargo install sd
cargo install sqlx-cli
cargo install wait-service
cargo install watchexec
cargo install websocat

# ------------------------------------------------------------------------------
# Install VSCode extensions
# ------------------------------------------------------------------------------
log "Installing VSCode extensions"
source $(dirname $0)/setup-vscode.sh

# ------------------------------------------------------------------------------
# Upgrade software
# ------------------------------------------------------------------------------
log "Upgrading software"
sudo apt upgrade -y

# ------------------------------------------------------------------------------
# Config GPG key
# ------------------------------------------------------------------------------
if [ ! -e ~/.gnupg/pubring.kbx ]; then
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
    ssh-keygen -t ed25519 -C "renatodinhani@gmail.com" -N "" -f ~/.ssh/dinhani
fi

# ------------------------------------------------------------------------------
# Config home and user
# ------------------------------------------------------------------------------
git config --global user.email "$EMAIL"
git config --global user.name "Renato Dinhani"
