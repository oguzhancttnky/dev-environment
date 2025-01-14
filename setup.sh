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
chsh -s /usr/bin/fish

echo "---Installing necessary tools---"

sudo apt-get install -y net-tools curl wget snapd

sudo apt-get install -y gcc

sudo apt-get install -y python3 python3-pip

JAVA_VERSION=$(ask_version "Java" "21")
echo "---Installing Java $JAVA_VERSION---"
sudo apt-get install -y openjdk-${JAVA_VERSION}-jdk

NODE_VERSION=$(ask_version "Node.js" "20")
echo "---Installing Node.js $NODE_VERSION---"
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | sudo bash -
sudo apt-get install -y nodejs

PNPM_VERSION=$(ask_version "Pnpm" "10.0.0")
echo "---Installing Pnpm $PNPM_VERSION---"
curl -fsSL https://get.pnpm.io/install.sh | env PNPM_VERSION=$PNPM_VERSION sh -

GO_VERSION=$(ask_version "Go" "1.21.0")
echo "---Installing Go $GO_VERSION---"
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz

echo "---Installing Fish plugins---"
fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
fish -c "fisher update"

echo "---System setup completed. Run 'make' to setup symlinks of dotfiles---"