#!/bin/bash

set -e

apt install -y \
  build-essential cmake check cython3 \
  libcurl4-openssl-dev libemu-dev libev-dev libglib2.0-dev \
  libloudmouth1-dev libnetfilter-queue-dev libnl-3-dev \
  libpcap-dev libssl-dev libtool libudns-dev \
  python3 python3-dev python3-bson python3-yaml \
  fonts-liberation

git clone https://github.com/DinoTools/dionaea.git /opt/dionaea-src
cd /opt/dionaea-src
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/dionaea ..
make -j$(nproc)
make install

mkdir -p /opt/dionaea/var/log/dionaea
mkdir -p /opt/dionaea/var/lib/dionaea/binaries
mkdir -p /opt/dionaea/var/lib/dionaea/bistreams

cat > /opt/dionaea/etc/dionaea/dionaea.cfg <<CFGEOF
[dionaea]
download.dir=/opt/dionaea/var/lib/dionaea/binaries
bistream.dir=/opt/dionaea/var/lib/dionaea/bistreams
listen.addresses=0.0.0.0

[logging]
handlers=log_json

[log_json]
handlers=file
filename=/opt/dionaea/var/log/dionaea/dionaea.json
CFGEOF

useradd -r -s /bin/false dionaea || true
chown -R dionaea:dionaea /opt/dionaea

cat > /etc/systemd/system/dionaea.service <<SERVICEEOF
[Unit]
Description=Dionaea Malware Honeypot
After=network.target

[Service]
Type=simple
User=dionaea
Group=dionaea
ExecStart=/opt/dionaea/bin/dionaea -c /opt/dionaea/etc/dionaea/dionaea.cfg -D
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable dionaea
systemctl start dionaea

echo "[OK] Dionaea instalado y activo"
