#!/bin/bash

set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== [1/6] Actualizando sistema ==="
apt update && apt upgrade -y
apt install -y apt-transport-https curl gnupg2 software-properties-common

echo "=== [2/6] Añadiendo repositorio Elastic 7.x ==="
curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic.gpg] https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list
apt update

echo "=== [3/6] Instalando Elasticsearch ==="
apt install -y elasticsearch

cat > /etc/elasticsearch/elasticsearch.yml <<'ESEOF'
cluster.name: ${cluster_name}
node.name: elk-siem-node
path.data: /var/lib/elasticsearch
path.logs: /var/log/elasticsearch
network.host: 0.0.0.0
http.port: 9200
transport.port: 9300
discovery.type: single-node
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
action.auto_create_index: true
action.destructive_requires_name: true
ESEOF

mkdir -p /etc/elasticsearch/jvm.options.d
cat > /etc/elasticsearch/jvm.options.d/heap.options <<'HEAPEOF'
-Xms4g
-Xmx4g
HEAPEOF

mkdir -p /etc/systemd/system/elasticsearch.service.d
cat > /etc/systemd/system/elasticsearch.service.d/override.conf <<'SYSEOF'
[Service]
LimitMEMLOCK=infinity
SYSEOF

systemctl daemon-reload
systemctl enable elasticsearch
systemctl start elasticsearch

echo "Esperando a Elasticsearch..."
for i in $(seq 1 90); do
  if curl -s -o /dev/null http://localhost:9200; then
    echo "Elasticsearch listo tras $i intentos"
    break
  fi
  echo "Esperando... ($i/90)"
  sleep 5
done

echo "=== Configurando contraseñas ==="
echo -e "y\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n${elastic_password}\n" | /usr/share/elasticsearch/bin/elasticsearch-setup-passwords interactive || true

# Verificar
curl -s -u elastic:${elastic_password} http://localhost:9200 || echo "WARN: Elasticsearch no responde con credenciales"
echo "[OK] Elasticsearch instalado"

echo "=== [4/6] Instalando Kibana ==="
apt install -y kibana

SECURITY_KEY=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 16)
REPORTING_KEY=$(openssl rand -hex 16)

cat > /etc/kibana/kibana.yml <<KBEOF
server.port: 5601
server.host: "0.0.0.0"
server.name: "${cluster_name}-siem"
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "${elastic_password}"
xpack.security.enabled: true
xpack.security.encryptionKey: "$SECURITY_KEY"
xpack.encryptedSavedObjects.encryptionKey: "$ENCRYPTION_KEY"
xpack.reporting.encryptionKey: "$REPORTING_KEY"
logging.root.level: info
KBEOF

systemctl enable kibana
systemctl start kibana
echo "[OK] Kibana instalado - puerto 5601"

echo "=== [5/6] Instalando Logstash ==="
apt install -y logstash

cat > /etc/logstash/conf.d/01-beats-input.conf <<'INPUTEOF'
input {
  beats {
    port => 5044
    host => "0.0.0.0"
  }
}
INPUTEOF

cat > /etc/logstash/conf.d/10-honeypot-filter.conf <<'FILTEREOF'
filter {
  if [fields][honeypot_type] == "cowrie" {
    json { source => "message" target => "cowrie" }
    mutate { add_field => { "honeypot" => "cowrie" } }
    if [cowrie][src_ip] {
      geoip {
        source => "[cowrie][src_ip]"
        target => "geoip"
      }
    }
  }
  if [fields][honeypot_type] == "dionaea" {
    json { source => "message" target => "dionaea" }
    mutate { add_field => { "honeypot" => "dionaea" } }
    if [dionaea][src_ip] {
      geoip {
        source => "[dionaea][src_ip]"
        target => "geoip"
      }
    }
  }
  if [fields][honeypot_type] == "web" {
    json { source => "message" target => "web_honeypot" }
    mutate { add_field => { "honeypot" => "web" } }
    if [web_honeypot][source_ip] {
      geoip {
        source => "[web_honeypot][source_ip]"
        target => "geoip"
      }
    }
  }
}
FILTEREOF

cat > /etc/logstash/conf.d/30-output.conf <<OUTPUTEOF
output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    user => "elastic"
    password => "${elastic_password}"
    index => "honeypot-%%{[honeypot]}-%%{+YYYY.MM.dd}"
  }
}
OUTPUTEOF

systemctl enable logstash
systemctl start logstash
echo "[OK] Logstash instalado - puerto 5044"

PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo "  HoneyCloud SIEM - Instalación OK"
echo "========================================"
echo "  Elasticsearch: http://localhost:9200"
echo "  Kibana:        http://$PRIVATE_IP:5601"
echo "  Logstash:      $PRIVATE_IP:5044"
echo "  Usuario:       elastic"
echo "========================================"
