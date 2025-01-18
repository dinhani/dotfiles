#!/bin/bash
source $(dirname $0)/setup-unix-functions.sh

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
cp alias.sh $DIR_SCRIPTS

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

# homebrew
export PATH=\$PATH:$(brew_dir)/bin
export PATH=\$PATH:$(brew_dir)/sbin
export PATH=\$PATH:$(brew_dir)/opt/python@3.13/libexec/bin

# system
ulimit -n 65365
EOF

# ------------------------------------------------------------------------------
# .bashrc
# ------------------------------------------------------------------------------
log "Configuring .bash_profile"
cat << EOF > ~/.bash_profile
source ~/.bashrc
EOF

log "Configuring .bashrc"
cat << EOF > ~/.bashrc
# common
source ~/.shell_common

# zoxide
eval "\$(zoxide init bash)"
EOF


# ------------------------------------------------------------------------------
# Install APT basic tools
# ------------------------------------------------------------------------------
log "Updating APT repositories"
sudo apt update

log "Upgrading APT software"
sudo apt upgrade -y

log "Installing APT build tools"
install_apt build-essential
install_apt curl

# ------------------------------------------------------------------------------
# Install Homebrew
# ------------------------------------------------------------------------------
if not_installed "brew"; then
    log "Installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    reload
fi

# ------------------------------------------------------------------------------
# Install Homebrew build tools
# ------------------------------------------------------------------------------
install_brew gcc
install_brew gcc@11
install_brew gcc@12
install_brew gcc@13

# ------------------------------------------------------------------------------
# Install Homebrew CLI tools
# ------------------------------------------------------------------------------
log "Installing Brew CLI tools"
install_brew bat
install_brew ripgrep
install_brew zoxide

# ------------------------------------------------------------------------------
# Install HomeAssistant dependencies
# ------------------------------------------------------------------------------
log "Installing Python"
install_brew python@3.13

log "Installing HA Brew tools"
install_brew ffmpeg

log "Installing HA APT libraries"
install_apt libpcap-dev
install_apt libturbojpeg-dev

log "Installing HA Python libraries"
pip install --break-system-packages \
    aiodhcpwatcher \
    aiodiscover \
    async-upnp-client \
    av \
    go2rtc-client \
    ha-ffmpeg \
    hassil \
    mutagen \
    numpy \
    pymicro-vad \
    PyNaCl \
    pyserial \
    pyspeex-noise \
    PyTurboJPEG \
    pyudev \
    zeroconf
pip install --break-system-packages \
    homeassistant \
    home-assistant-frontend \
    home-assistant-intents