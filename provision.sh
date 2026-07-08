#!/usr/bin/env bash
set -euo pipefail

# Provisioning script for Debian 12 Vagrant VM
# Installs Docker, Docker Compose, and Make

echo "==> Updating package indices..."
sudo apt-get update -y

echo "==> Installing basic prerequisites..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    make \
    software-properties-common

echo "==> Setting up Docker's official GPG key and repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "==> Updating package index with Docker repository..."
sudo apt-get update -y

echo "==> Installing Docker Engine, CLI, and Compose plugin..."
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

echo "==> Adding vagrant user to the docker group..."
sudo usermod -aG docker vagrant

echo "==> Enabling and starting Docker service..."
sudo systemctl enable docker
sudo systemctl start docker

echo "==> Provisioning complete!"
