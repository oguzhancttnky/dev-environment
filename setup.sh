#!/bin/bash

set -euo pipefail

ask_version() {
    local tool_name=$1
    local default_version=$2
    read -p "Enter the version of $tool_name to install (Press Enter to use default version: $tool_name $default_version): " version
    # If version is empty, use default version
    echo "${version:-$default_version}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

apt_install_latest() {
    local packages_to_install=()

    for package in "$@"; do
        local installed_version
        local candidate_version

        installed_version=$(dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true)
        candidate_version=$(apt-cache policy "$package" | awk '/Candidate:/ {print $2}')

        if [ -n "$installed_version" ] && [ "$installed_version" = "$candidate_version" ]; then
            echo "---$package is already up to date ($installed_version)---"
        else
            packages_to_install+=("$package")
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        sudo apt-get install -y "${packages_to_install[@]}"
    fi
}

snap_install_latest() {
    local classic=""

    if [ "${1:-}" = "--classic" ]; then
        classic="--classic"
        shift
    fi

    for package in "$@"; do
        if snap list "$package" >/dev/null 2>&1; then
            sudo snap refresh "$package"
        else
            sudo snap install $classic "$package"
        fi
    done
}

JAVA_VERSION=$(ask_version "Java" "25")
NODE_VERSION=$(ask_version "Node.js" "26")
GO_VERSION=$(ask_version "Go" "1.26.3")

echo "---Setting Bash as the default shell---"
current_shell=$(getent passwd "$USER" | cut -d: -f7)
if [ "$current_shell" != "/bin/bash" ] && [ "$current_shell" != "/usr/bin/bash" ]; then
    sudo chsh -s /bin/bash "$USER"
else
    echo "---Bash is already the default shell---"
fi

echo "---Installing necessary tools---"

apt_install_latest net-tools ca-certificates curl wget snapd fzf build-essential libfuse2 git-lfs gpaste-2 gnome-shell-extension-gpaste ripgrep fd-find bat eza jq btop pipx gh
mkdir -p ~/.local/bin
ln -sf /usr/bin/fdfind ~/.local/bin/fd
ln -sf /usr/bin/batcat ~/.local/bin/bat

echo "---Installing Catppuccin theme for bat---"
bat_themes="$(batcat --config-dir)/themes"
mkdir -p "$bat_themes"
curl -fsSL "https://raw.githubusercontent.com/catppuccin/bat/main/themes/Catppuccin%20Mocha.tmTheme" -o "$bat_themes/Catppuccin Mocha.tmTheme"
batcat cache --build >/dev/null

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\"" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
apt_install_latest docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER

echo "---Installing Java, Node.js, Go, Python, Rust, Kotlin---"
echo "---Installing Java $JAVA_VERSION---"
apt_install_latest openjdk-${JAVA_VERSION}-jdk

echo "---Installing Node.js $NODE_VERSION---"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
sudo apt-get update -y
apt_install_latest nodejs

echo "---Installing Global PNPM---"
latest_pnpm_version=$(npm view pnpm version)
if command_exists pnpm && [ "$(pnpm --version)" = "$latest_pnpm_version" ]; then
    echo "---PNPM is already up to date ($latest_pnpm_version)---"
else
    sudo npm install -g pnpm@latest
fi

echo "---Installing Go $GO_VERSION---"
if [ -x /usr/local/go/bin/go ] && /usr/local/go/bin/go version | grep -q "go${GO_VERSION}"; then
    echo "---Go $GO_VERSION is already installed---"
else
    wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz
fi

echo "---Installing Miniconda---"
if [ -x ~/miniconda3/bin/conda ]; then
    ~/miniconda3/bin/conda update -y -n base conda
else
    mkdir -p ~/miniconda3
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
    bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
    rm ~/miniconda3/miniconda.sh
fi

echo "---Installing Rust and Cargo---"
if [ -x ~/.cargo/bin/rustup ]; then
    ~/.cargo/bin/rustup update
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

echo "---Installing Starship prompt---"
latest_starship_version=$(curl -fsSL https://api.github.com/repos/starship/starship/releases/latest | jq -r '.tag_name | ltrimstr("v")')
if command_exists starship && starship --version | grep -q "$latest_starship_version"; then
    echo "---Starship is already up to date ($latest_starship_version)---"
else
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b ~/.local/bin
fi

echo "---Installing ble.sh (fish-like autosuggestions and highlighting for Bash)---"
blesh_tmp=$(mktemp -d)
curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar -xJf - -C "$blesh_tmp"
bash "$blesh_tmp/ble-nightly/ble.sh" --install ~/.local/share
rm -rf "$blesh_tmp"

echo "---Installing Ollama---"
latest_ollama_version=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | jq -r '.tag_name | ltrimstr("v")')
if command_exists ollama && ollama --version | grep -q "$latest_ollama_version"; then
    echo "---Ollama is already up to date ($latest_ollama_version)---"
else
    curl -fsSL https://ollama.com/install.sh | sh
fi

# Snap Installs
echo "---Installing Tools from Snap---"
snap_install_latest --classic code sublime-text sublime-merge kotlin
snap_install_latest pgadmin4 postman bruno localsend another-redis-desktop-manager vlc zoom-client superproductivity beekeeper-studio

echo "---Customizing GNOME desktop (configure in desktop/desktop.conf)---"
./desktop/setup-desktop.sh

echo "---System setup completed. Run 'make' to setup symlinks of dotfiles---"
