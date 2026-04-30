#!/bin/bash
set -e

apt install -y git python3-virtualenv python3-dev libssl-dev libffi-dev build-essential

useradd -r -s /bin/false cowrie || true

git clone https://github.com/cowrie/cowrie.git /opt/cowrie
cd /opt/cowrie

python3 -m virtualenv cowrie-env
source cowrie-env/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cp etc/cowrie.cfg.dist etc/cowrie.cfg
sed -i 's/#hostname = svr04/hostname = server01/' etc/cowrie.cfg
sed -i 's/#listen_endpoints = tcp:2222/listen_endpoints = tcp:2222/' etc/cowrie.cfg
sed -i 's/#enabled = false/enabled = true/' etc/cowrie.cfg

iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222

chown -R cowrie:cowrie /opt/cowrie

cat > /etc/systemd/system/cowrie.service <<SERVICEEOF
[Unit]
Description=Cowrie SSH/Telnet Honeypot
After=network.target

[Service]
Type=simple
User=cowrie
Group=cowrie
WorkingDirectory=/opt/cowrie
ExecStart=/opt/cowrie/cowrie-env/bin/python3 /opt/cowrie/bin/cowrie start -n
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable cowrie
systemctl start cowrie

echo "[OK] Cowrie instalado y activo en puerto 2222 (redirigido desde 22)"