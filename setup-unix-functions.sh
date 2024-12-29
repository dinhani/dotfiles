# ------------------------------------------------------------------------------
# Dirs
# ------------------------------------------------------------------------------
DIR_DOWNLOADS=~/downloads
DIR_SCRIPTS=~/scripts
DIR_TOOLS=~/tools
DIR_PROJECTS=~/projects

# ------------------------------------------------------------------------------
# Checks / Dirs
# ------------------------------------------------------------------------------

# Checks if a command/program exists.
function installed() {
    command -v "$1" >/dev/null 2>&1
}

# Checks if a command/program not exists.
function not_installed() {
    ! installed "$1"
}

# Checks if script is running on Linux.
function is_linux() {
    [[ "$(uname -s)" == "Linux" ]]
}

# Checks if script is running on Mac.
function is_mac() {
    is_mac_intel || is_mac_arm
}

# Checks if script is running on Mac with Intel processor.
function is_mac_intel() {
    [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]]
}

# Checks if script is running on Mac with ARM processor.
function is_mac_arm() {
    [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]
}


# Returns Homebrew directory.
function brew_dir() {
    if is_mac_intel; then
        echo "/usr/local"
    elif is_mac_arm; then
        echo "/opt/homebrew"
    elif is_linux; then
        echo "/home/linuxbrew/.linuxbrew"
    else
        brew --prefix
    fi
}

# ------------------------------------------------------------------------------
# Installation
# ------------------------------------------------------------------------------

# Install something with APT.
function install_apt() {
    if ! dpkg -l |  cut -d' ' -f3 | grep -qw $1; then
        log "APT installing: $1"
        sudo apt-get install -y $1
    else
        log "APT skipping: $1"
    fi
}

# Install something with brew.
function install_brew() {
    if ! brew list -1 | grep -q "^$1\$"; then
            log "Homebrew installing: $1"
        brew install $1
    else
        log "Homebrew skipping: $1"
    fi
}

# Install something with ASDF.
function install_asdf() {
    lang=$1
    version=$2

    # install plugin and lang
    log "ASDF installing: $lang $version"
    asdf plugin add $lang
    asdf install $lang $version

    # add to .tool-versions
    echo "$lang $version" >> ~/.tool-versions
    reload
}

# Install something for VSCode or Cursor
function install_vscode() {
    if installed "code"; then
        if ! code --list-extensions | grep -qi "^$1\$"; then
            log "Installing VSCode extension: $1"
            code --install-extension $1
        else
            log "VSCode skipping: $1"
        fi
    fi

    if installed "cursor"; then
        if ! cursor --list-extensions | grep -qi "^$1\$"; then
            log "Installing Cursor extension: $1"
            cursor --install-extension $1
        else
            log "Cursor skipping: $1"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Download / Extract
# ------------------------------------------------------------------------------

# Download a file from an URL to a target file.
function download() {
    local url=$1
    local target=$2
    local extract_to=$3

    # download
    if [[ $target == /* ]]; then
        target=$target
    else
        target=$DIR_DOWNLOADS/$target
    fi

    log "Downloading: $url -> $target"
    curl -o "$target" -fsSL "$url"

    # make executable
    if [[ $target == /usr/local/bin/* ]]; then
        executable $target
    fi

    # extract if necessary
    if [ -n "$extract_to" ]; then
        extract $target $extract_to
    fi
}

# Extract a compressed file to a target directory/file.
function extract() {
    # extract
    local source=$1
    local target=$2
    log "Extracting: $source => $target"
    case "$source" in
        *.tar.gz)
            tar -C $target -xzvf $source
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# Log a formatted message to stderr.
log() {
    echo "" 1>&2
    echo -e "* [$(date +"%Y-%m-%d %H:%M:%S")] $@" 1>&2;
}

# Reload .bashrc
function reload() {
    source ~/.bashrc
}