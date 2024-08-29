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
iptables -A OUTPUT -t nat -p tcp --dport 1:65535 ! -d 127.0.0.1  -j DNAT --to-destination 127.0.0.1:1200
iptables -L -t nat

# generate identity key
/app/keygen-ed25519 --secret /app/id.sec --public /app/id.pub

# olas agent service setup
# Install pip
python -m ensurepip --upgrade
pip install --upgrade pip

# Install open-autonomy
pip install open-autonomy[all]
pip install open-aea-ledger-ethereum
autonomy init --remote --ipfs --author anon_kun
autonomy packages init
autonomy fetch valory/hello_world:0.1.0:bafybeifvk5uvlnmugnefhdxp26p6q2krc5i5ga6hlwgg6xyyn5b6hknmru --service

cd /app/hello_world
autonomy build-image

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

autonomy deploy build keys.json -ltm

cd /app/hello_world/abci_build

# starting supervisord
cat /etc/supervisord.conf
/app/supervisord