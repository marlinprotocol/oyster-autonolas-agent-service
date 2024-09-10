#!/bin/sh

set -e

# setting an address for loopback
ifconfig lo 127.0.0.1
ip addr

# adding a default route
ip route add default dev lo src 127.0.0.1
ip route

# iptables rules to route traffic to transparent proxy
iptables -t nat -N DOCKER
iptables -t nat -A OUTPUT -d 172.17.0.0/16 -j DOCKER
iptables -A OUTPUT -t nat -p tcp --dport 1:65535 ! -d 127.0.0.1  -j DNAT --to-destination 127.0.0.1:1200
iptables -L -t nat

# generate identity key
/app/keygen-ed25519 --secret /app/id.sec --public /app/id.pub

# olas agent service setup

# here be dragons
cat /app/iptablesPath.txt
ls -lath `cat /app/iptablesPath.txt`
rm -rf `cat /app/iptablesPath.txt`

# Start transparent proxy
/app/ip-to-vsock-transparent --vsock-addr 3:1200 --ip-addr 127.0.0.1:1200 &
PROXY_PID=$!

# Start DNS proxy
/app/dnsproxy -u https://1.1.1.1/dns-query -v &
DNS_PID=$!

# Wait for DNS and proxy to be ready
sleep 10

export HOME=/app
export POETRY_HOME=/app/.poetry
export PATH=$POETRY_HOME/bin:$PATH

# todo - check if autonomy pre-requisites are installed
cd /app
poetry config virtualenvs.in-project true
poetry new olas-agent
cd olas-agent

# Add dependencies
poetry add open-autonomy[all] open-aea-ledger-ethereum

# Initialize autonomy
poetry run autonomy init --remote --ipfs --author anon_kun
poetry run autonomy packages init
poetry run autonomy fetch valory/hello_world:0.1.0:bafybeifvk5uvlnmugnefhdxp26p6q2krc5i5ga6hlwgg6xyyn5b6hknmru --service

cd /app/olas-agent/hello_world

# Set up Docker DNS configuration
echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 8.8.4.4" >> /etc/resolv.conf

# Start Docker daemon
/bin/dockerd &
DOCKER_PID=$!

# Wait for Docker to be ready
sleep 30

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

# # Debug: Check DNS resolution after Docker start
# nslookup registry.autonolas.tech || { echo "DNS resolution failed"; exit 1; }

# Build the image
poetry run autonomy build-image

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