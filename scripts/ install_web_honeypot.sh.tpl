#!/bin/bash
set -e

apt install -y python3-pip python3-dev nginx git

pip3 install snare --break-system-packages

mkdir -p /var/log/web-honeypot

snare --port 8080 --host-ip 0.0.0.0 --page-dir /opt/snare/pages \
  --clone --target http://example.com &>/dev/null &

iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-port 8080

cat > /etc/systemd/system/web-honeypot.service <<SERVICEEOF
[Unit]
Description=SNARE Web Honeypot
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/snare --port 8080 --host-ip 0.0.0.0 --page-dir /opt/snare/pages
Restart=always
RestartSec=5
StandardOutput=append:/var/log/web-honeypot/snare.json
StandardError=append:/var/log/web-honeypot/snare-error.log

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable web-honeypot
systemctl start web-honeypot

echo "[OK] Web Honeypot (SNARE) instalado en puerto 8080 (redirigido desde 80/443)"
