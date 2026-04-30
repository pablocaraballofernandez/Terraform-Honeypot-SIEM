# HoneyCloud-SIEM

Infraestructura de honeypots desplegada en AWS con Terraform, monitorizada por un SIEM centralizado con ELK Stack.

## Arquitectura

```
                    ┌──────────────────────────────┐
                    │        INTERNET               │
                    └──────────┬───────────────────┘
                               │
                    ┌──────────▼───────────────────┐
                    │         AWS VPC               │
                    │       10.0.0.0/16             │
                    │                               │
  ┌─────────────────┴──────┐    ┌──────────────────┴──────┐
  │   Honeypot (t3.medium) │    │   ELK SIEM (t3.large)   │
  │                        │    │                          │
  │  ● Cowrie (SSH)        │    │  ● Elasticsearch 7.x    │
  │    Puerto 22 → 2222    │    │    Puerto 9200           │
  │                        │    │                          │
  │  ● Dionaea (Docker)    │    │  ● Kibana                │
  │    21, 445, 3306, 1433 │    │    Puerto 5601           │
  │                        │    │                          │
  │  ● Web Honeypot        │    │  ● Logstash              │
  │    Puerto 80 → 8080    │    │    Puerto 5044           │
  │                        │    │                          │
  │  ● Filebeat ──────────────▶│  (recibe logs)           │
  │                        │    │                          │
  │  SSH admin: 22222      │    │  GeoIP integrado         │
  └────────────────────────┘    └──────────────────────────┘
```

## Componentes

### Honeypots

| Honeypot | Descripción | Puertos | Instalación |
|----------|-------------|---------|-------------|
| **Cowrie** | Honeypot SSH/Telnet que simula un servidor Linux. Registra credenciales, comandos y sesiones de los atacantes. | 22 → 2222 | Git + virtualenv + Twisted |
| **Dionaea** | Honeypot de malware que emula servicios vulnerables (FTP, SMB, MySQL, MSSQL). Captura binarios maliciosos. | 21, 445, 3306, 1433 | Docker (dinotools/dionaea) |
| **Web Honeypot** | Servidor web que clona una página real y registra todos los requests (SQL injection, XSS, directory traversal, etc.). | 80 → 8080 | Python + SNARE clone |

### SIEM (ELK Stack 7.x)

| Componente | Descripción | Puerto |
|------------|-------------|--------|
| **Elasticsearch** | Almacena y busca los logs de los honeypots. | 9200 |
| **Kibana** | Dashboard web para visualizar ataques, geolocalización de IPs y análisis. | 5601 |
| **Logstash** | Recibe logs de Filebeat, los parsea y enriquece con GeoIP antes de enviarlos a Elasticsearch. | 5044 |
| **Filebeat** | Instalado en el honeypot. Recolecta logs de Cowrie, Dionaea y Web Honeypot y los envía a Logstash. | - |

## Requisitos

- **AWS CLI** configurado con credenciales (`aws configure`)
- **Terraform** >= 1.0
- **Par de claves SSH** (ed25519 recomendado)

## Despliegue

### 1. Clonar el repositorio

```bash
git clone https://github.com/pablocaraballofernandez/Terraform-Honeypot-SIEM.git
cd Terraform-Honeypot-SIEM
```

### 2. Crear `terraform.tfvars`

Copia el ejemplo y completa con tus valores:

```hcl
region                 = "eu-west-1"
enviroment             = "lab"
project_name           = "honeycloud"
admin_IP               = ["TU_IP_PUBLICA/32"]
honeypot_instance_type = "t3.medium"
elk_instance_type      = "t3.large"
enable_cowrie          = true
enable_dionaea         = true
enable_web_honeypot    = true
ssh_public_key         = "ssh-ed25519 AAAA... tu-clave-publica"
clave_geo_IP           = "tu-clave-maxmind"
kibana_basic_auth_user = "honeyadmin"
elastic_password       = "tu-contraseña-segura"
ami                    = "ami-0ec2a5ff1be0688fa"
```

Para obtener tu IP pública:

```bash
curl ifconfig.me
```

### 3. Desplegar

```bash
terraform init
terraform plan
terraform apply
```

El despliegue tarda aproximadamente 15-20 minutos (instalación de ELK + honeypots).

### 4. Verificar

```bash
# Obtener IPs
terraform output siem_public_ip
terraform output honeypot_public_ip

# Acceder a Kibana
http://<siem_public_ip>:5601

# Conectarse al honeypot (admin)
ssh -i ~/.ssh/tu-clave -p 22222 ubuntu@<honeypot_public_ip>

# Conectarse al SIEM (admin)
ssh -i ~/.ssh/tu-clave ubuntu@<siem_public_ip>
```

### 5. Comprobar que la instalación terminó

En cada instancia:

```bash
tail -5 /var/log/cloud-init-output.log
```

Debe mostrar `Instalación OK` al final.

## Acceso a Kibana

1. Abrir `http://<siem_public_ip>:5601`
2. Usuario: `elastic` / Contraseña: la definida en `terraform.tfvars`
3. Ir a **Stack Management** → **Index Patterns** → Crear `honeypot-*` con campo `@timestamp`
4. Ir a **Discover** para ver los logs
5. Ir a **Maps** para ver la geolocalización de los atacantes

## Estructura del proyecto

```
HoneyCloud-SIEM/
├── provider.tf           # Configuración del provider AWS
├── main.tf               # Instancias EC2 (SIEM + Honeypot)
├── network.tf            # VPC, subnet, internet gateway, rutas
├── security_groups.tf    # Security groups (ELK + Honeypot)
├── variables.tf          # Declaración de variables
├── output.tf             # Outputs (IPs, URLs, comandos SSH)
├── terraform.tfvars      # Valores de variables (NO subir al repo)
├── scripts/
│   ├── setup_elk.sh.tpl      # Script de instalación del SIEM
│   └── setup_honeypot.sh.tpl # Script de instalación de honeypots
├── .gitignore
└── README.md
```

## Índices en Elasticsearch

| Índice | Contenido |
|--------|-----------|
| `honeypot-cowrie-*` | Sesiones SSH, credenciales, comandos ejecutados |
| `honeypot-dionaea-*` | Conexiones a servicios vulnerables, malware capturado |
| `honeypot-web-*` | Requests HTTP, intentos de inyección, paths escaneados |

## Seguridad

- El **SSH real** de administración del honeypot está en el puerto **22222**, accesible solo desde la IP del admin.
- El **puerto 22 del honeypot** es Cowrie (el honeypot SSH), abierto a internet intencionadamente.
- **Kibana** solo es accesible desde la IP del admin.
- **Elasticsearch** y **Logstash** solo aceptan conexiones desde la VPC.
- Si tu IP cambia, actualiza `admin_IP` en `terraform.tfvars` y ejecuta `terraform apply`.

## Notas técnicas

- **Dionaea** se ejecuta en Docker porque su código fuente utiliza funciones de OpenSSL que fueron eliminadas en la versión 3.0 (incluida en Ubuntu 22.04). Aunque compila sin errores, al ejecutarse produce un crash (segmentation fault). La imagen Docker `dinotools/dionaea` incluye sus propias librerías compatibles, evitando este problema.- **Cowrie** requiere `pip install -e .` para registrarse como plugin de Twisted. Sin esto, `twistd cowrie` falla con "Unknown command".
- **SNARE** necesita TANNER (servidor de análisis) que no tiene imagen Docker pública disponible. Se usa un script Python custom que sirve la página clonada con Content-Type correcto leyendo `meta.json`.
- Las reglas de **iptables** se insertan con `-I PREROUTING 1` para que queden antes de la cadena DOCKER.
- **Logstash 7.x** incluye su propia base de datos GeoIP, no es necesario instalar MaxMind.

## Destruir la infraestructura

```bash
terraform destroy
```

## Licencia

MIT
