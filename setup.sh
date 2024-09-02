#!/bin/sh

set -e

# setting an address for loopback
ifconfig lo 127.0.0.1

# ifconfig lo 127.0.0.1 up
ip addr

echo "127.0.0.1 localhost" > /etc/hosts

# adding a default route
ip route add default dev lo src 127.0.0.1
ip route

# iptables rules to route traffic to transparent proxy
iptables -A OUTPUT -t nat -p tcp --dport 1:65535 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:1200
iptables -L -t nat

# iptables -t nat -A OUTPUT -p tcp -d 13.42.161.185 --dport 443 -j ACCEPT
# iptables -t nat -A OUTPUT -p tcp -d 13.41.115.114 --dport 443 -j ACCEPT
# iptables -t nat -A OUTPUT -p tcp -d 52.56.57.111 --dport 443 -j ACCEPT
# iptables -A OUTPUT -t nat -p tcp --dport 1:65535 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:1200
# iptables -L -t nat

# generate identity key
/app/keygen-ed25519 --secret /app/id.sec --public /app/id.pub

# olas agent service setup
# Start DNS proxy
/app/dnsproxy -u https://1.1.1.1/dns-query -v &
DNS_PID=$!

# Start transparent proxy
/app/ip-to-vsock-transparent --vsock-addr 3:1200 --ip-addr 127.0.0.1:1200 &
PROXY_PID=$!

# Wait for DNS and proxy to be ready
sleep 10

# # Debug: Check DNS resolution
# echo "Checking DNS resolution before setting resolv.conf"
# nslookup google.com || { echo "DNS resolution failed before setting resolv.conf"; exit 1; }

# # Additional Debugging: Check DNS resolution for registry.autonolas.tech
# echo "Checking DNS resolution for registry.autonolas.tech"
# nslookup registry.autonolas.tech || { echo "DNS resolution failed for registry.autonolas.tech"; exit 1; }

# # Additional Debugging: Check IP routes
# echo "Checking IP routes"
# ip route show

# # Additional Debugging: Check IP rules
# echo "Checking IP rules"
# ip rule show

# # Additional Debugging: Check if we can establish a TCP connection to registry.autonolas.tech
# echo "Checking TCP connection to registry.autonolas.tech"
# nc -zv registry.autonolas.tech 443 || { echo "TCP connection to registry.autonolas.tech failed"; exit 1; }


# # Additional Debugging: Check connectivity to registry.autonolas.tech
# echo "Checking connectivity to registry.autonolas.tech"
# ping -c 4 registry.autonolas.tech || { echo "Ping to registry.autonolas.tech failed"; exit 1; }

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

# Start Docker daemon with legacy iptables
/bin/dockerd --iptables=false &
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