#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/7] Actualizando sistema ==="
apt update && apt upgrade -y

echo "=== [2/7] Moviendo SSH real al puerto 22222 ==="
sed -i 's/^#Port 22/Port 22222/' /etc/ssh/sshd_config
sed -i 's/^Port 22$/Port 22222/' /etc/ssh/sshd_config
systemctl restart sshd || true

%{ if enable_cowrie }
echo "=== [3/7] Instalando Cowrie ==="

apt install -y git python3-virtualenv python3-venv python3-dev \
  libssl-dev libffi-dev build-essential authbind

adduser --disabled-password --gecos "" cowrie || true


sudo -u cowrie -H git clone https://github.com/cowrie/cowrie.git /home/cowrie/cowrie || true

chown -R cowrie:cowrie /home/cowrie/cowrie


sudo -u cowrie -H bash -c '
  export HOME=/home/cowrie
  cd /home/cowrie/cowrie
  python3 -m venv cowrie-env
  source cowrie-env/bin/activate
  pip install --upgrade pip
  pip install --upgrade -r requirements.txt
  git config --global --add safe.directory /home/cowrie/cowrie
  pip install -e .
'

sudo -u cowrie cp /home/cowrie/cowrie/etc/cowrie.cfg.dist /home/cowrie/cowrie/etc/cowrie.cfg

cat >> /home/cowrie/cowrie/etc/cowrie.cfg <<'COWRIECFG'

[output_jsonlog]
enabled = true
logfile = var/log/cowrie/cowrie.json
epoch_timestamp = false
COWRIECFG

chown cowrie:cowrie /home/cowrie/cowrie/etc/cowrie.cfg


cat > /etc/systemd/system/cowrie.service <<'SERVICEEOF'
[Unit]
Description=Cowrie SSH/Telnet Honeypot
After=network.target

[Service]
Type=simple
User=cowrie
Group=cowrie
WorkingDirectory=/home/cowrie/cowrie
ExecStart=/home/cowrie/cowrie/cowrie-env/bin/twistd --nodaemon --pidfile= cowrie
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF


iptables -t nat -I PREROUTING 1 -p tcp --dport 22 -j REDIRECT --to-port 2222

systemctl daemon-reload
systemctl enable cowrie
systemctl start cowrie
echo "[OK] Cowrie instalado en puerto 2222 (redirigido desde 22)"
%{ endif }

%{ if enable_dionaea }
echo "=== [4/7] Instalando Dionaea (Docker) ==="

apt install -y docker.io
systemctl enable docker
systemctl start docker

mkdir -p /opt/dionaea/var/log/dionaea
mkdir -p /opt/dionaea/var/lib/dionaea

docker run -d --name dionaea \
  --restart always \
  -p 21:21 \
  -p 42:42 \
  -p 69:69/udp \
  -p 135:135 \
  -p 445:445 \
  -p 1433:1433 \
  -p 1723:1723 \
  -p 1883:1883 \
  -p 1900:1900/udp \
  -p 3306:3306 \
  -p 5060:5060 \
  -p 5060:5060/udp \
  -p 5061:5061 \
  -p 11211:11211 \
  -v /opt/dionaea/var/log:/opt/dionaea/var/log \
  -v /opt/dionaea/var/lib:/opt/dionaea/var/lib \
  dinotools/dionaea

echo "[OK] Dionaea (Docker) instalado"
%{ endif }

%{ if enable_web_honeypot }
echo "=== [5/7] Instalando Web Honeypot ==="



apt install -y python3-venv python3-dev git

git clone https://github.com/mushorg/snare.git /opt/snare-src || true
python3 -m venv /opt/snare-env
/opt/snare-env/bin/pip install --upgrade pip
/opt/snare-env/bin/pip install -r /opt/snare-src/requirements.txt
cd /opt/snare-src && /opt/snare-env/bin/pip install .

/opt/snare-env/bin/clone --target http://example.com --path /opt/snare || true

mkdir -p /opt/snare


cat > /opt/web-honeypot.py <<'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, datetime, os

LOG_FILE = "/opt/snare/web-honeypot.json"
WEB_DIR = "/opt/snare/snare/pages/example.com"

# Cargar mapeo de rutas desde meta.json
with open(os.path.join(WEB_DIR, "meta.json")) as f:
    META = json.load(f)

class HoneypotHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            path = "/index.html"

        if path in META:
            file_hash = META[path]["hash"]
            headers = {h_key: h_val for d in META[path]["headers"] for h_key, h_val in d.items()}
            filepath = os.path.join(WEB_DIR, file_hash)
            with open(filepath, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", headers.get("Content-Type", "text/html"))
            self.send_header("Server", headers.get("Server", "nginx"))
            self.end_headers()
            self.wfile.write(content)
        else:
            if "/status_404" in META:
                file_hash = META["/status_404"]["hash"]
                filepath = os.path.join(WEB_DIR, file_hash)
                with open(filepath, "rb") as f:
                    content = f.read()
                self.send_response(404)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_response(404)
                self.end_headers()

        self.log_attack()

    def do_POST(self):
        self.log_attack()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()

    def log_attack(self):
        entry = {
            "timestamp": datetime.datetime.utcnow().isoformat(),
            "source_ip": self.client_address[0],
            "method": self.command,
            "path": self.path,
            "headers": dict(self.headers)
        }
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")

    def log_message(self, format, *args):
        pass

HTTPServer(("0.0.0.0", 8080), HoneypotHandler).serve_forever()
PYEOF

cat > /etc/systemd/system/web-honeypot.service <<'SERVICEEOF'
[Unit]
Description=Web Honeypot
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/web-honeypot.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICEEOF


iptables -t nat -I PREROUTING 1 -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -I PREROUTING 2 -p tcp --dport 443 -j REDIRECT --to-port 8080

systemctl daemon-reload
systemctl enable web-honeypot
systemctl start web-honeypot
echo "[OK] Web honeypot instalado en puerto 8080 (redirigido desde 80/443)"
%{ endif }

echo "=== [6/7] Instalando Filebeat ==="

curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
apt update
apt install -y filebeat

cat > /etc/filebeat/filebeat.yml <<'FBEOF'
filebeat.inputs:
  - type: log
    enabled: ${enable_cowrie}
    paths:
      - /home/cowrie/cowrie/var/log/cowrie/cowrie.json
    fields:
      honeypot_type: cowrie
    fields_under_root: false
    json.keys_under_root: false

  - type: log
    enabled: ${enable_dionaea}
    paths:
      - /opt/dionaea/var/log/dionaea/*.json
      - /opt/dionaea/var/log/dionaea/dionaea.log
    fields:
      honeypot_type: dionaea
    fields_under_root: false

  - type: log
    enabled: ${enable_web_honeypot}
    paths:
      - /opt/snare/web-honeypot.json
    fields:
      honeypot_type: web
    fields_under_root: false

output.logstash:
  hosts: ["${siem_private_ip}:5044"]

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
FBEOF

systemctl enable filebeat
systemctl start filebeat
echo "[OK] Filebeat instalado - enviando logs a ${siem_private_ip}:5044"

echo "=== [7/7] Persistiendo reglas iptables ==="
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
apt install -y iptables-persistent

echo ""
echo "========================================"
echo "  HoneyCloud Honeypot - Instalación OK"
echo "========================================"
echo "  Cowrie (SSH):     puerto 22 -> 2222"
echo "  Dionaea (Docker): 21,445,3306,1433"
echo "  Web Honeypot:     puerto 80 -> 8080"
echo "  Filebeat:         -> ${siem_private_ip}:5044"
echo "  SSH admin real:   puerto 22222"
echo "========================================"
