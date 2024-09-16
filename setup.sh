#!/bin/sh

set -e

# setting an address for loopback
ifconfig lo 127.0.0.1
ip addr

echo "127.0.0.1 localhost" > /etc/hosts

# adding a default route
ip route add default dev lo src 127.0.0.1
ip route

# iptables rules to route traffic to transparent proxy
iptables -t nat -N DOCKER
iptables -t nat -A OUTPUT -d 172.17.0.0/16 -j DOCKER
iptables -A OUTPUT -t nat -p tcp --dport 1:65535 ! -d 127.0.0.1  -j DNAT --to-destination 127.0.0.1:1200
iptables -L -t nat
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# Allow HTTP and HTTPS traffic
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
/app/dnsproxy -u https://1.1.1.1/dns-query &
DNS_PID=$!

# Wait for DNS and proxy to be ready
sleep 10

# Check if DNS proxy is running and listening on port 53
echo "Checking if DNS proxy is running and listening on port 53"
if ! netstat -tuln | grep -q ':53'; then
  echo "DNS proxy is not running or not listening on port 53. Exiting."
fi
echo "DNS proxy is running and listening on port 53"

# Test DNS proxy on the host
echo "Testing DNS proxy on the host"
nslookup registry.autonolas.tech 127.0.0.1 || {
  echo "Failed to resolve DNS on the host using DNS proxy. Exiting."
}

echo "DNS proxy test on the host passed"

# Test communication through transparent proxy and DNS proxy on the host
echo "Testing communication through transparent proxy and DNS proxy on the host"
wget --no-check-certificate --verbose --spider https://registry.autonolas.tech || {
  echo "Failed to communicate through transparent proxy and DNS proxy on the host. Exiting."
}

export HOME=/app
export POETRY_HOME=/app/.poetry
export PATH=$POETRY_HOME/bin:$PATH

# Configure Docker daemon to use host's network
# iptables set true tells Docker to modify the iptables rules on the host
# ip-forward set true enables IP forwarding in the Docker daemon. IP forwarding allows the system to forward packets from one network interface to another, which is necessary for routing traffic between containers and the host network.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "dns": ["172.17.0.1"],
  "dns-opts": ["ndots:1"],
  "iptables": false,
  "ip-forward": true,
  "ip-masq": false,
  "userland-proxy": false,
  "hosts": ["unix:///var/run/docker.sock"]
}
EOF

export DOCKER_HOST=unix:///var/run/docker.sock

# Start Docker daemon
/bin/dockerd &
DOCKER_PID=$!

# Wait for Docker to be ready
sleep 20

# Check if Docker is running
if docker info > /dev/null 2>&1; then
    echo "Docker is running"
else
    echo "Docker is not running. Exiting."
    exit 1
fi

# Check if Docker socket exists
if [ ! -S /var/run/docker.sock ]; then
    echo "Docker socket not found. Exiting."
    exit 1
fi
echo "Docker socket found"

echo "Check docker /etc/resolv.conf"
docker run --rm alpine cat /etc/resolv.conf

# Test communication from within a Docker container
echo "Testing communication from within a Docker container"
docker run --rm alpine sh -c "wget --no-check-certificate --spider https://registry.autonolas.tech" || {
  echo "if iptables set true look for error - wget: can't connect to remote host (52.56.57.111): Operation timed out otherwise look for error - wget: can't connect to remote host (13.42.161.185): Host is unreachable above"
}

# Test communication from within a Docker container using host network
echo "Testing communication from within a Docker container using host network"
docker run --rm --network host alpine sh -c "wget --no-check-certificate --spider https://registry.autonolas.tech" || {
  echo "look for error - wget: server returned error: HTTP/1.1 404 Not Found"
}

cd /app
poetry config virtualenvs.in-project true
poetry new olas-agent
cd /app/olas-agent

poetry add open-autonomy[all] open-aea-ledger-ethereum
poetry run autonomy init --remote --ipfs --author anon_kun
poetry run autonomy packages init
poetry run autonomy fetch valory/hello_world:0.1.0:bafybeifvk5uvlnmugnefhdxp26p6q2krc5i5ga6hlwgg6xyyn5b6hknmru --service

cd /app/olas-agent/hello_world

echo "Running poetry with proxy settings"
poetry -vvv run autonomy build-image

# # Test communication from within a Docker container with explicit proxy
# echo "Testing communication from within a Docker container with explicit proxy"
# docker run --rm --network host alpine sh -c "export http_proxy=127.0.0.1:1200; wget --no-check-certificate --spider https://registry.autonolas.tech" || {
#   echo "Docker container cannot reach registry.autonolas.tech using explicit proxy. Exiting."
# }

# echo "Docker container communication test with explicit proxy passed"




# # Check if DNS proxy is running
# if ! pgrep -f dnsproxy > /dev/null; then
#     echo "DNS proxy failed to start. Exiting."
#     exit 1
# fi

# # Check loopback interface
# if ! ifconfig lo | grep "inet 127.0.0.1" > /dev/null; then
#     echo "Loopback interface not configured correctly. Exiting."
#     exit 1
# fi

# export HOME=/app
# export POETRY_HOME=/app/.poetry
# export PATH=$POETRY_HOME/bin:$PATH

# # todo - check if autonomy pre-requisites are installed
# cd /app
# poetry config virtualenvs.in-project true
# poetry new olas-agent
# cd olas-agent
# poetry run python --version
# poetry add open-autonomy[all] open-aea-ledger-ethereum

# # Add dependencies
# poetry add open-autonomy[all] open-aea-ledger-ethereum

# # Initialize autonomy
# poetry run autonomy init --remote --ipfs --author anon_kun
# poetry run autonomy packages init
# poetry run autonomy fetch valory/hello_world:0.1.0:bafybeifvk5uvlnmugnefhdxp26p6q2krc5i5ga6hlwgg6xyyn5b6hknmru --service

# cd /app/olas-agent/hello_world

# # Modify Docker daemon settings
# mkdir -p /etc/docker
# cat > /etc/docker/daemon.json <<EOF
# {
#   "dns": ["172.17.0.1"],
#   "dns-search": [],
#   "dns-opts": ["ndots:1"],
#   "hosts": ["unix:///var/run/docker.sock"]
# }
# EOF

# # Create resolv.conf file for Docker
# mkdir -p /run/systemd/resolve
# cat > /run/systemd/resolve/resolv.conf <<EOF
# nameserver 172.17.0.1
# EOF

# # Start Docker daemon
# dockerd &
# DOCKER_PID=$!

# # Wait for Docker to be ready
# sleep 20

# # Check if Docker socket exists
# if [ ! -S /var/run/docker.sock ]; then
#     echo "Docker socket not found. Exiting."
#     exit 1
# fi

# # Check if Docker is running
# if docker info > /dev/null 2>&1; then
#     echo "Docker is running, proceeding with the build."
# else
#     echo "Docker is not running. Exiting."
#     exit 1
# fi

# # Test Docker DNS resolution
# echo "Testing Docker DNS resolution:"
# docker run --rm --network host alpine nslookup registry.autonolas.tech || echo "Docker DNS resolution failed"

# # Verify iptables rules
# echo "Verifying iptables rules:"
# iptables -L -t nat

# # Test DNS resolution again
# echo "Testing DNS resolution:"
# nslookup registry.autonolas.tech || {
#   echo "DNS resolution failed. Exiting."
#   exit 1
# }

# # Check network connectivity from within the enclave
# echo "Checking network connectivity from within the enclave"
# wget -O- --timeout=30 --no-check-certificate -v https://registry.autonolas.tech || {
#   echo "Enclave cannot reach registry.autonolas.tech. Exiting."
# }

# # Check network connectivity from within a Docker container
# echo "Checking network connectivity from within a Docker container"
# docker run --rm --network host alpine sh -c "wget -T 30 --no-check-certificate --spider http://google.com" || {
#   echo "Docker container cannot reach http://google.com using host network mode. Exiting."
# }

# # Check if Docker is listening on the required ports
# echo "Checking if Docker is listening on the required ports:"
# netstat -tuln | grep -E '(::2376|:443)' || echo "Docker is not listening on the required ports"

# echo "DNS resolution and network connectivity successful. Proceeding with build."
# poetry -vvv run autonomy build-image

# cat > keys.json << EOF
# [
#   {
#     "address": "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955",
#     "private_key": "0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356"
#   }
# ]
# EOF
# export ALL_PARTICIPANTS='[
#     "0x14dC79964da2C08b23698B3D3cc7Ca32193d9955"
# ]'

# poetry run autonomy deploy build keys.json -ltm

# # Stop Docker, DNS proxy and transparent proxy
# kill $DOCKER_PID
# kill $DNS_PID
# kill $PROXY_PID

# # starting supervisord
# cat /etc/supervisord.conf
# /app/supervisord