#!/usr/bin/env bash
# stacks/node.sh — Node.js alt package managers + quality/coverage tools
# Runs INSIDE container after base.sh (installs Node.js + npm, then tools)
set -e
export DEBIAN_FRONTEND=noninteractive

# Node.js 22 LTS (via NodeSource) — moved here from base.sh
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "Installing Node stack..."

# Alt package managers
npm install -g pnpm yarn

# Bun runtime
curl -fsSL https://bun.sh/install | bash

# Coverage (uses V8 native coverage)
npm install -g c8

# Linting
npm install -g eslint

# Formatting
npm install -g prettier

echo "Node stack complete"
