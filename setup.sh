#!/bin/bash

ask_version() {
    local tool_name=$1
    local default_version=$2
    read -p "Enter the version of $tool_name to install (Press Enter to use default version: $tool_name $default_version): " version
    # If version is empty, use default version
    echo "${version:-$default_version}"
}

echo "---Installing Fish and setting it as the default shell---"
sudo apt-get update
sudo apt-get install -y fish
sudo chsh -s /usr/bin/fish

echo "---Installing necessary tools (net-tools, ca-certificates, curl, wget, snapd, fzf, build-essential, libfuse2, python, docker, openjdk, nodejs, go, rust, cargo, rustup)---"

sudo apt-get install -y net-tools ca-certificates curl wget snapd fzf build-essential libfuse2

sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
bash -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable"' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER

JAVA_VERSION=$(ask_version "Java" "25")
NODE_VERSION=$(ask_version "Node.js" "22")
GO_VERSION=$(ask_version "Go" "1.25.4")
PYTHON_VERSION=$(ask_version "Python" "3.13")

echo "---Installing Java $JAVA_VERSION---"
sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk

echo "---Installing Node.js $NODE_VERSION---"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
sudo apt-get install -y nodejs

echo "---Installing Global PNPM---"
sudo npm install -g pnpm

echo "---Installing Go $GO_VERSION---"
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

echo "---Installing Python $PYTHON_VERSION---"
sudo add-apt-repository -y ppa:deadsnakes/ppa >/dev/null 2>&1
sudo apt-get update
sudo apt-get install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-venv python${PYTHON_VERSION}-dev python3-pip

echo "---Installing Rust and Cargo---"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

echo "---Installing Fish plugins---"
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher jorgebucaran/autopair.fish"
fish -c "fisher update"

# Snap Installs
echo "---Installing Tools from Snap---"
sudo snap install code --classic
sudo snap install sublime-merge --classic
sudo snap install pgadmin4 postman bruno localsend another-redis-desktop-manager vlc zoom-client sublime-text superproductivity beekeeper-studio

echo "---System setup completed. Run 'make' to setup symlinks of dotfiles---"