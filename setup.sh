#!/bin/bash

set -euo pipefail

ask_version() {
    local tool_name=$1
    local default_version=$2
    read -p "Enter the version of $tool_name to install (Press Enter to use default version: $tool_name $default_version): " version
    # If version is empty, use default version
    echo "${version:-$default_version}"
}

JAVA_VERSION=$(ask_version "Java" "25")
NODE_VERSION=$(ask_version "Node.js" "22")
GO_VERSION=$(ask_version "Go" "1.25.4")

echo "---Installing Fish and setting it as the default shell---"
sudo apt-add-repository -y ppa:fish-shell/release-4 >/dev/null 2>&1
sudo apt-get update -y
sudo apt-get install -y fish
sudo chsh -s /usr/bin/fish "$USER"

echo "---Installing necessary tools---"

sudo apt-get install -y net-tools ca-certificates curl wget snapd fzf build-essential libfuse2 git-lfs gpaste-2 gnome-shell-extension-gpaste ripgrep fd-find bat jq btop pipx gh
mkdir -p ~/.local/bin
ln -sf /usr/bin/fdfind ~/.local/bin/fd
ln -sf /usr/bin/batcat ~/.local/bin/bat

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\"" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER

echo "---Installing Java, Node.js, Go, Python, Rust, Kotlin---"
echo "---Installing Java $JAVA_VERSION---"
sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk

echo "---Installing Node.js $NODE_VERSION---"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
sudo apt-get update -y
sudo apt-get install -y nodejs

echo "---Installing Global PNPM---"
sudo npm install -g pnpm

echo "---Installing Go $GO_VERSION---"
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

echo "---Installing Miniconda---"
mkdir -p ~/miniconda3
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda3/miniconda.sh
bash ~/miniconda3/miniconda.sh -b -u -p ~/miniconda3
rm ~/miniconda3/miniconda.sh

echo "---Installing Rust and Cargo---"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

echo "---Installing Fish plugins---"
rm -rf ~/.config/fish/functions ~/.config/fish/completions ~/.config/fish/conf.d
mkdir -p ~/.config/fish/functions ~/.config/fish/completions ~/.config/fish/conf.d
chown -R $USER:$USER ~/.config/fish

fish -c 'curl -sL https://git.io/fisher | source; fisher install jorgebucaran/fisher'
fish -c "fisher install (cat ./fish/fish_plugins)"
fish -c "tide configure --auto --style=Lean --prompt_colors='16 colors' --show_time=No --lean_prompt_height='One line' --prompt_spacing=Compact --icons='Few icons' --transient=No"
# Disable version display
fish -c "set -U tide_right_prompt_items (string match -v -r 'node|python|java|rustc|go' \$tide_right_prompt_items)"
fish -c "set -U tide_left_prompt_items (string match -v -r 'node|python|java|rustc|go' \$tide_left_prompt_items)"
cp fish/fish-ai.ini ~/.config/

echo "---Installing Ollama---"
curl -fsSL https://ollama.com/install.sh | sh

# Snap Installs
echo "---Installing Tools from Snap---"
sudo snap install --classic code
sudo snap install --classic sublime-text
sudo snap install --classic sublime-merge
sudo snap install --classic kotlin
sudo snap install pgadmin4 postman bruno localsend another-redis-desktop-manager vlc zoom-client superproductivity beekeeper-studio

echo "---System setup completed. Run 'make' to setup symlinks of dotfiles---"
