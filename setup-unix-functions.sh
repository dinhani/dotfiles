DOWNLOADS=~/downloads

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

# Checks if script is running on Mac with Inter processor.
function is_mac_intel() {
    [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]]
}

# Checks if script is running on Mac with ARM processor.
function is_mac_arm() {
    [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]
}

# Return the Homebrew directory based on the operating system.
function brew_cellar() {
    if is_mac_intel; then
        echo "/usr/local/Cellar"
    elif is_mac_arm; then
        echo "/opt/homebrew/Cellar"
    elif is_linux; then
        echo "/home/linuxbrew/.linuxbrew/Cellar"
    else
        echo ""
    fi
}

# Return the Homebrew binary directory based on the operating system.
function brew_bin() {
    if is_mac_intel; then
        echo "/usr/local/bin"
    elif is_mac_arm; then
        echo "/opt/homebrew/bin"
    elif is_linux; then
        echo "/home/linuxbrew/.linuxbrew/bin"
    else
        echo ""
    fi
}

# Return the Homebrew library directory based on the operating system.
function brew_lib() {
    if is_mac_intel; then
        echo "/usr/local/lib"
    elif is_mac_arm; then
        echo "/opt/homebrew/lib"
    elif is_linux; then
        echo "/home/linuxbrew/.linuxbrew/lib"
    else
        echo ""
    fi
}

# Return the Homebrew opt directory based on the operating system.
function brew_opt() {
    if is_mac_intel; then
        echo "/usr/local/opt"
    elif is_mac_arm; then
        echo "/opt/homebrew/opt"
    elif is_linux; then
        echo "/home/linuxbrew/.linuxbrew/opt"
    else
        echo ""
    fi
}


# ------------------------------------------------------------------------------
# Installation
# ------------------------------------------------------------------------------

# Install something with APT.
function apt_install() {
    log "APT installing: $1"
    if ! dpkg -l |  cut -d' ' -f3 | grep -qw $1; then
        sudo apt-get install -y $1
    fi
}

# Install something with brew.
function brew_install() {
    log "Homebrew installing: $1"
    if ! brew list -1 | grep -q "^$1\$"; then
        brew install $1
    fi
}

# Install something with ASDF.
function asdf_install() {
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
        target=$DOWNLOADS/$target
    fi

    log "Downloading: $url -> $target"
    sudo curl -o "$target" -fsSL "$url"

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
            sudo tar -C $target -xzvf $source
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