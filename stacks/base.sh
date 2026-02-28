#!/usr/bin/env bash
# stacks/base.sh — Core golden image: Docker, Claude Code, Python 3, dev tools
# Usage: called by sandbox-setup, runs INSIDE the Incus container via incus exec
set -e
export DEBIAN_FRONTEND=noninteractive

echo "Installing base tools..."

apt-get update
apt-get install -y \
  curl git tmux openssh-server ripgrep jq htop wget unzip \
  build-essential ca-certificates gnupg lsb-release \
  python3 python3-pip python3-venv

# Docker (official repo)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Claude Code (native installer — self-contained, no Node.js needed)
curl -fsSL https://claude.ai/install.sh | bash
# Ensure claude is on PATH for non-interactive shells (incus exec)
ln -sf /root/.local/bin/claude /usr/local/bin/claude

# SSH config — key-based auth only (host key injected by sandbox-create)
mkdir -p /run/sshd /root/.ssh
chmod 700 /root/.ssh
sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
passwd -l root

# Enable services
systemctl enable docker
systemctl enable ssh

# Create workspace
mkdir -p /workspace

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Base golden image setup complete"
