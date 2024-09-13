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
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -L -t nat

# Allow outbound HTTP and HTTPS traffic
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

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

# Check if DNS proxy is running
if ! pgrep -f dnsproxy > /dev/null; then
    echo "DNS proxy failed to start. Exiting."
    exit 1
fi

# Check loopback interface
if ! ifconfig lo | grep "inet 127.0.0.1" > /dev/null; then
    echo "Loopback interface not configured correctly. Exiting."
    exit 1
fi

export HOME=/app
export POETRY_HOME=/app/.poetry
export PATH=$POETRY_HOME/bin:$PATH

# todo - check if autonomy pre-requisites are installed
cd /app
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

# Modify Docker daemon settings
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "dns": ["172.17.0.1"],
  "dns-search": [],
  "dns-opts": ["ndots:1"],
  "hosts": ["unix:///var/run/docker.sock"]
}
EOF

# Create resolv.conf file for Docker
mkdir -p /run/systemd/resolve
cat > /run/systemd/resolve/resolv.conf <<EOF
nameserver 172.17.0.1
EOF

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

# Test Docker DNS resolution
echo "Testing Docker DNS resolution:"
docker --rm alpine nslookup registry.autonolas.tech || echo "Docker DNS resolution failed"

# Verify iptables rules
echo "Verifying iptables rules:"
iptables -L -t nat

# Test DNS resolution again
echo "Testing DNS resolution:"
nslookup registry.autonolas.tech || {
  echo "DNS resolution failed. Exiting."
  exit 1
}

# echo "Checking if Docker is listening on the required ports:"
# netstat -tuln | grep -E '(:2375|:2376|:443)' || echo "Docker is not listening on the required ports"

# # Check network connectivity from within a Docker container
# echo "Checking network connectivity from within a Docker container"
#docker run --rm --network host alpine sh -c "wget -T 30 --spider https://registry.autonolas.tech" || {
#     echo "Docker container cannot reach registry.autonolas.tech using host network mode. Exiting."

# # Check network connectivity from within the enclave
# echo "Checking network connectivity from within the enclave"
# wget -T 30 --no-check-certificate --spider https://registry.autonolas.tech || {
#   echo "Enclave cannot reach registry.autonolas.tech. Exiting."
#   exit 1
# }

# poetry run autonomy build-image
echo "DNS resolution and network connectivity successful. Proceeding with build."
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