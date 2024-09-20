#!/bin/sh

set -e

# setting an address for loopback
ifconfig lo 127.0.0.1
ip addr

# adding a default route
ip route add default dev lo src 127.0.0.1
ip route

# iptables rule to route traffic to transparent proxy
iptables -t nat -I OUTPUT 1 -p tcp --dport 1:65535 ! -d 127.0.0.1 -j DNAT --to-destination 127.0.0.1:1200

echo "127.0.0.1 localhost" > /etc/hosts
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Start DNS proxy
/app/dnsproxy -u https://1.1.1.1/dns-query &
DNS_PID=$!

# Start transparent proxy for outbound traffic
/app/ip-to-vsock-transparent --vsock-addr 3:1200 --ip-addr 0.0.0.0:1200 &
PROXY_PID=$!

# Wait for DNS and proxy to be ready
sleep 10

mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<EOF
{
  "dns": ["172.17.0.1"],
  "hosts": ["unix:///var/run/docker.sock"]
}
EOF

# Start Docker daemon
/bin/dockerd --debug  &
DOCKER_PID=$!

# Wait for Docker to be ready
sleep 20

iptables -t nat -I PREROUTING 1 -i docker0 -p tcp --dport 1:65535 -j DNAT --to-destination 172.17.0.1:1200

iptables -A FORWARD -i docker0 -o lo -j ACCEPT
iptables -A FORWARD -i lo -o docker0 -j ACCEPT

echo "Testing communication from docker"
docker run --rm alpine sh -c "
    nslookup ifconfig.me || echo 'DNS resolution failed'
    nc -zv ifconfig.me 443 || echo 'TCP connectivity failed'
    wget --no-check-certificate -O- -q https://ifconfig.me || echo 'wget failed'
"
# generate identity key
/app/keygen-ed25519 --secret /app/id.sec --public /app/id.pub

export HOME=/app
export POETRY_HOME=/app/.poetry
export PATH=$POETRY_HOME/bin:$PATH

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
wait $DOCKER_PID

# starting supervisord
cat /etc/supervisord.conf
/app/supervisord