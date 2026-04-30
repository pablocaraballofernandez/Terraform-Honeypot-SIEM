#!/bin/bash
# ======================== Filebeat - Log Shipper =============================
set -e

# Instalar Filebeat
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
apt update
apt install -y filebeat

# Copiar configuración (inyectada por templatefile)
cat > /etc/filebeat/filebeat.yml <<FBEOF
filebeat.inputs:
  - type: log
    enabled: ${enable_cowrie}
    paths:
      - /opt/cowrie/var/log/cowrie/cowrie.json*
    fields:
      honeypot_type: cowrie
    fields_under_root: false

  - type: log
    enabled: ${enable_dionaea}
    paths:
      - /opt/dionaea/var/log/dionaea/dionaea.json
    fields:
      honeypot_type: dionaea
    fields_under_root: false

  - type: log
    enabled: ${enable_web_honeypot}
    paths:
      - /var/log/web-honeypot/*.json
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

echo "[OK] Filebeat instalado y enviando logs a ${siem_private_ip}"
