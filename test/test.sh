#!/bin/sh

set -e

# Install Docker
# Install Docker
echo "Installing Docker..."
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Poetry
echo "Installing Poetry..."
curl -sSL https://install.python-poetry.org | python3.10 -

# Add Poetry to PATH
export PATH="/root/.local/bin:$PATH"

# Create pyproject.toml file
cat > pyproject.toml << EOF
[tool.poetry]
name = "olas-agent"
version = "0.1.0"
description = "Autonolas agent service"
authors = ["Marlin <ayushkaul@marlin.org>"]

[tool.poetry.dependencies]
python = "^3.10"

[build-system]
requires = ["poetry-core>=1.0.0"]
build-backend = "poetry.core.masonry.api"
EOF

# Ensure Poetry uses Python 3.10
poetry env use $(which python3.10)

# Check Python version
poetry run python --version

# Add dependencies
poetry add open-autonomy[all] open-aea-ledger-ethereum

export HOME=/app
export POETRY_HOME=/app/.poetry
export PATH=$POETRY_HOME/bin:$PATH

# todo - check if autonomy pre-requisites are installed
poetry config virtualenvs.in-project true
poetry new olas-agent
cd olas-agent
poetry run python --version
poetry add open-autonomy[all] open-aea-ledger-ethereum

# Add dependencies
poetry add open-autonomy[all] open-aea-ledger-ethereum

# Initialize autonomy
poetry run autonomy init --remote --ipfs --author anon_kun
poetry run autonomy packages init
poetry run autonomy fetch valory/hello_world:0.1.0:bafybeifvk5uvlnmugnefhdxp26p6q2krc5i5ga6hlwgg6xyyn5b6hknmru --service

cd /app/olas-agent/hello_world

# Start Docker daemon
dockerd &
DOCKER_PID=$!

# Wait for Docker to be ready
sleep 20

# Check if Docker socket exists
if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket not found. Exiting."
    exit 1
fi

# Check if Docker is running
if docker info > /dev/null 2>&1; then
    echo "Docker is running, proceeding with the build."
else
    echo "Docker is not running. Exiting."
    exit 1
fi

# Verify iptables rules
echo "Verifying iptables rules:"
iptables -L -t nat

# poetry run autonomy build-image
poetry -vvv run autonomy build-image

cat > keys.json << EOF
[
  {
    "address": "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955",
    "private_key": "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"
  }
]
EOF
export ALL_PARTICIPANTS='[
    "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"
]'

poetry run autonomy deploy build keys.json -ltm

# Stop Docker, DNS proxy and transparent proxy
kill $DOCKER_PID
kill $DNS_PID
kill $PROXY_PID

# starting supervisord
cat /etc/supervisord.conf
/app/supervisord