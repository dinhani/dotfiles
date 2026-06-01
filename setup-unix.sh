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
# Install .shell_common
# ------------------------------------------------------------------------------
log "Configuring common shell setup"

cat << EOF > ~/.shell_common
# aliases / functions
source $DIR_SCRIPTS/alias.sh

# terminal
export HISTSIZE=100000
export HISTFILESIZE=100000
export EDITOR=hx
export VISUAL=hx

# windows
export APPDATA=/mnt/c/Users/Renato/AppData/Roaming/
export LOCALAPPDATA=/mnt/c/Users/Renato/AppData/Local/

# docker / colima
if is_mac; then
    export DOCKER_HOST="unix://\$HOME/.colima/default/docker.sock"
fi

# homebrew
export PATH=$(brew_dir)/bin:\$PATH
export PATH=$(brew_dir)/sbin:\$PATH
export CMAKE_LIBRARY_PATH=$(brew_dir)/lib
export CMAKE_SYSTEM_LIBRARY_PATH=$(brew_dir)/lib
export CPATH=$(brew_dir)/include
export LD_LIBRARY_PATH=$(brew_dir)/lib
export LIBRARY_PATH=$(brew_dir)/lib
export PKG_CONFIG_PATH=$(brew_dir)/lib/pkgconfig

# additional tools
export PATH=\$PATH:$HOME/.local/bin

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
export PATH=\$HOME/.asdf/shims:\$PATH

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
if [ -e ~/.shell_private ]; then
    source ~/.shell_private
fi

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
if [ -e ~/.shell_private ]; then
    source ~/.shell_private
fi

# oh-my-zsh
export ZSH=$HOME/.oh-my-zsh
source $HOME/.oh-my-zsh/oh-my-zsh.sh

# ls colors
export LS_COLORS="$LS_COLORS:ow=1;34:tw=1;34:"
zstyle ':completion:*' list-colors \${(s.:.)LS_COLORS}

# starship
eval "\$(starship init zsh)"

# zoxide
eval "\$(zoxide init zsh)"
EOF

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    log "Installing Oh My ZSH"
    CHSH=no KEEP_ZSHRC=no RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

reload

# ------------------------------------------------------------------------------
# Install configurations
# ------------------------------------------------------------------------------

# config: aliases
log "Configuring aliases"
cp scripts/alias.sh $DIR_SCRIPTS

# config: editor
if is_linux; then
    log "Configuring editor"
    sudo update-alternatives --install /usr/bin/editor editor "$(brew_dir)/bin/hx" 100
fi

# config: gpg
if ! gpg --list-secret-keys "$EMAIL" >/dev/null 2>&1; then
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

# config: ssh
if [ ! -e ~/.ssh/dinhani.pub ]; then
    log "Configuring SSH key"
    ssh-keygen -t ed25519 -C "$EMAIL" -N "" -f ~/.ssh/dinhani
fi

# config: git
log "Configuring Git"
git config --global user.email "$EMAIL"
git config --global user.name "Renato Dinhani"

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
# Install MAS (Mac App Store CLI)
# ------------------------------------------------------------------------------
if is_mac; then
    install_brew mas
fi

# ------------------------------------------------------------------------------
# Install Desktop tools
# ------------------------------------------------------------------------------
if is_mac; then
    # hardware
    install_brew elgato-stream-deck
    install_brew logitech-g-hub
    install_brew linearmouse

    # docs
    install_brew notable
    install_brew obsidian

    # media
    install_brew spotify

    # terminal
    install_brew ghostty
    install_brew warp

    # dev editors (individual)
    if not_installed "code"; then
        install_brew visual-studio-code
    fi
    if not_installed "cursor"; then
        install_brew "cursor"
    fi
    install_brew rstudio

    # dev editors (jetbrains)
    install_brew jetbrains-toolbox
    install_brew clion
    install_brew datagrip
    install_brew dataspell
    install_brew goland
    install_brew intellij-idea
    install_brew phpstorm
    install_brew pycharm
    install_brew rider
    install_brew rubymine
    install_brew rustrover
    install_brew webstorm

    # dev tools
    install_brew bruno
    install_brew devtoys

    # utils
    install_brew google-chrome

    # app store
    install_mas 937984704  # Amphetamine
    install_mas 6448461551 # Command X
    install_mas 411643860  # DaisyDisk
    install_mas 1111570163 # GrandPerspective
    install_mas 441258766  # Magnet
    install_mas 1606145041 # Sleeve

    # personal only
    if is_personal; then
        install_mas 1136220934 # Infuse
        install_mas 510620098  # MediaInfo
    fi

    # work only
    if is_work; then
        install_brew slack
    fi
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
install_brew pkgconf
install_brew protobuf
install_brew re2c

log "Installing build tools libraries"
install_brew bzip2
install_brew freetype
install_brew gmp
install_brew icu4c@78
install_brew jpeg
install_brew krb5
install_brew libffi
install_brew libiconv
install_brew libpng
install_brew libsodium
install_brew libxml2
install_brew libyaml
install_brew libzip
install_brew oniguruma
install_brew openssl@3
install_brew readline
install_brew sqlite
install_brew webp
install_brew xz
install_brew zlib

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
install_brew claude-code
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
if not_installed "tsv-pretty"; then
    log "Installing tsv-utils"
    brew install rothgar/tap/tsv-utils
fi
install_brew unzip
install_brew util-linux
install_brew w3m
install_brew wait4x
install_brew watchexec
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
    install_brew mas

    install_brew colima
    install_brew docker
    install_brew docker-compose

    if [ ! -L /var/run/docker.sock ]; then
        log "Configuring Colima docker socket"
        sudo ln -sfn $HOME/.colima/default/docker.sock /var/run/docker.sock
    fi
fi

# ------------------------------------------------------------------------------
# Install programming languages
# ------------------------------------------------------------------------------
install_asdf dotnet          10.0.300
install_asdf golang          1.26.3
install_asdf gradle          9.5.1
install_asdf java            openjdk-26.0.1
install_asdf julia           1.12.6
install_asdf kotlin          2.3.21
install_asdf lua             5.5.0
install_asdf maven           3.9.16
install_asdf nodejs          26.1.0
install_asdf powershell-core 7.6.1
install_asdf python          3.14.5
install_asdf R               4.6.0
install_asdf ruby            4.0.4
install_asdf zig             0.16.0

# ------------------------------------------------------------------------------
# Install Rust
# ------------------------------------------------------------------------------
if not_installed "rustup"; then
    log "Installing rustup"
    curl https://sh.rustup.rs -sSf | sh -s -- -y
fi

# ------------------------------------------------------------------------------
# Install programming languages extensions
# ------------------------------------------------------------------------------

# Golang
log "Installing Golang extensions"
not_installed "dlv"                      && go install github.com/go-delve/delve/cmd/dlv@latest
not_installed "golangci-lint"            && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
not_installed "golangci-lint-langserver" && go install github.com/nametake/golangci-lint-langserver@latest
not_installed "gopls"                    && go install golang.org/x/tools/gopls@latest

# Python
log "Installing Python extensions and tools"
pip3 install --break-system-packages alphabet-detector black boto3 beautifulsoup4 codetiming colorama cmap dpath deep-translator dotmap httpie isbnlib lazy-object-proxy lxml matplotlib mycli networkx numpy openai pandas polars pgcli psycopg2-binary python-dateutil python-lsp-server PyYAML requests ruff scipy selenium sqlitedict simple-chalk structlog unidecode tqdm toml tomli yamale yapf

# Ruby
log "Installing Ruby extensions and tools"
gem install --conservative activesupport pry nokogiri pp pry puma rails rufo sinatra solargraph webrick tomlrb tomlib

# Rust
log "Installing Rust toolchains"
rustup toolchain install stable
rustup toolchain install nightly

for component in clippy rustfmt rust-analyzer; do
    rustup component add "$component"
    rustup +nightly component add "$component"
done

log "Installing Rust extensions"
not_installed "cargo-expand" && cargo install --locked cargo-expand

# ------------------------------------------------------------------------------
# Install VSCode extensions
# ------------------------------------------------------------------------------
if not_installed "code" && not_installed "cursor"; then
    log_skip "VSCode and Cursor not installed, skipping extensions"
fi

# General

# WSL / SSH
install_vscode ms-vscode-remote.remote-wsl         # WSL
install_vscode ms-vscode-remote.remote-ssh         # SSH

# General
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
install_vscode bierner.markdown-mermaid            # Mermaid
install_vscode ms-vscode.PowerShell                # PowerShell
install_vscode ms-python.python                    # Python
install_vscode rust-lang.rust-analyzer             # Rust
install_vscode tamasfe.even-better-toml            # TOML
install_vscode redhat.vscode-xml                   # XML

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
