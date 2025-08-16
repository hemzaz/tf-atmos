#!/bin/bash
# Development Environment Setup Script
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="tf-atmos-idp"
REQUIRED_TOOLS=("docker" "docker-compose" "git" "curl")
GITHUB_REPO_URL="https://github.com/company/tf-atmos"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is not installed. Please install it and try again."
            exit 1
        fi
        log_success "$tool is available"
    done
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
    log_success "Docker daemon is running"
    
    # Check Docker Compose version
    if ! docker-compose version &> /dev/null; then
        log_warning "docker-compose not found, trying docker compose plugin"
        if ! docker compose version &> /dev/null; then
            log_error "Neither docker-compose nor docker compose plugin found"
            exit 1
        fi
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi
    log_success "Docker Compose is available: $COMPOSE_CMD"
}

create_env_files() {
    log_info "Creating environment configuration files..."
    
    # Create .env file for development
    if [[ ! -f .env ]]; then
        cat > .env << EOF
# Development Environment Configuration
COMPOSE_PROJECT_NAME=${PROJECT_NAME}
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# GitHub Integration (optional for development)
GITHUB_TOKEN=
AUTH_GITHUB_CLIENT_ID=
AUTH_GITHUB_CLIENT_SECRET=

# Atlantis Configuration (optional)
ATLANTIS_GH_USER=atlantis
ATLANTIS_WEBHOOK_SECRET=dev-webhook-secret
ATLANTIS_REPO_ALLOWLIST=github.com/company/*

# AWS Configuration (uses local credentials)
AWS_DEFAULT_REGION=us-east-1

# Database Configuration (automatically set by Docker Compose)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres_root

# API Configuration
PLATFORM_API_URL=http://localhost:8000
PLATFORM_DEFAULT_TENANT=dev
PLATFORM_DEFAULT_ACCOUNT=local

# Feature Flags
ENABLE_MONITORING=true
ENABLE_SECURITY_SCANNING=true
ENABLE_K8S_LOCAL=true
EOF
        log_success "Created .env file"
    else
        log_info ".env file already exists, skipping creation"
    fi
    
    # Create Backstage local config
    mkdir -p platform/backstage
    if [[ ! -f platform/backstage/app-config.local.yaml ]]; then
        cat > platform/backstage/app-config.local.yaml << 'EOF'
# Local development configuration for Backstage
app:
  title: IDP - Development
  baseUrl: http://localhost:3000

backend:
  baseUrl: http://localhost:7007
  database:
    client: pg
    connection:
      host: postgres
      port: 5432
      user: backstage
      password: backstage_dev
      database: backstage

auth:
  # Allow guest access for development
  providers:
    guest:
      dangerouslyAllowOutsideDevelopment: true

catalog:
  locations:
    # Local file system locations for development
    - type: file
      target: /app/examples/**/catalog-info.yaml
    - type: file
      target: /app/platform/catalog/*.yaml

# Enable debug logging for development
logging:
  level: debug
EOF
        log_success "Created Backstage local configuration"
    else
        log_info "Backstage local config already exists, skipping creation"
    fi
}

create_monitoring_configs() {
    log_info "Setting up monitoring configuration..."
    
    # Prometheus configuration
    mkdir -p monitoring/prometheus
    if [[ ! -f monitoring/prometheus/prometheus.yml ]]; then
        cat > monitoring/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts/*.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'backstage'
    static_configs:
      - targets: ['backstage:7007']
    metrics_path: '/api/app/metrics'

  - job_name: 'platform-api'
    static_configs:
      - targets: ['platform-api:8000']
    metrics_path: '/metrics'

  - job_name: 'postgres-exporter'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis-exporter'
    static_configs:
      - targets: ['redis-exporter:9121']
EOF
        log_success "Created Prometheus configuration"
    fi
    
    # Loki configuration
    mkdir -p monitoring/loki
    if [[ ! -f monitoring/loki/loki-config.yml ]]; then
        cat > monitoring/loki/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
  max_transfer_retries: 0

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb:
    directory: /loki/index

  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s
EOF
        log_success "Created Loki configuration"
    fi
    
    # Promtail configuration
    mkdir -p monitoring/promtail
    if [[ ! -f monitoring/promtail/promtail-config.yml ]]; then
        cat > monitoring/promtail/promtail-config.yml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: containers
    static_configs:
      - targets:
          - localhost
        labels:
          job: containerlogs
          __path__: /var/lib/docker/containers/*/*log

    pipeline_stages:
      - json:
          expressions:
            output: log
            stream: stream
            attrs:
      - json:
          expressions:
            tag: attrs.tag
          source: attrs
      - regex:
          expression: (?P<container_name>(?:[^|]*))\|
          source: tag
      - timestamp:
          format: RFC3339Nano
          source: time
      - labels:
          stream:
          container_name:
      - output:
          source: output
EOF
        log_success "Created Promtail configuration"
    fi
}

create_database_init_script() {
    log_info "Creating database initialization script..."
    
    mkdir -p scripts/database
    if [[ ! -f scripts/database/init-multiple-databases.sh ]]; then
        cat > scripts/database/init-multiple-databases.sh << 'EOF'
#!/bin/bash
set -e
set -u

function create_user_and_database() {
    local database=$1
    local password="${database}_dev"
    echo "Creating user and database '$database'"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE USER $database WITH PASSWORD '$password';
        CREATE DATABASE $database;
        GRANT ALL PRIVILEGES ON DATABASE $database TO $database;
EOSQL
}

if [ -n "$POSTGRES_MULTIPLE_DATABASES" ]; then
    echo "Multiple database creation requested: $POSTGRES_MULTIPLE_DATABASES"
    for db in $(echo $POSTGRES_MULTIPLE_DATABASES | tr ',' ' '); do
        create_user_and_database $db
    done
    echo "Multiple databases created"
fi
EOF
        chmod +x scripts/database/init-multiple-databases.sh
        log_success "Created database initialization script"
    fi
}

setup_development_scripts() {
    log_info "Creating development helper scripts..."
    
    # Create start script
    cat > scripts/start-dev.sh << 'EOF'
#!/bin/bash
# Start development environment
set -euo pipefail

# Load environment variables
if [[ -f .env ]]; then
    export $(grep -v '^#' .env | xargs)
fi

# Determine compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

echo "Starting IDP development environment..."

# Pull latest images
$COMPOSE_CMD pull

# Build and start services
$COMPOSE_CMD up --build -d

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# Check service health
echo "Checking service health..."
$COMPOSE_CMD ps

echo "Development environment is ready!"
echo "- Backstage UI: http://localhost:3000"
echo "- Platform API: http://localhost:8000"
echo "- Grafana: http://localhost:3001 (admin/admin_dev)"
echo "- Prometheus: http://localhost:9090"
echo "- Atlantis: http://localhost:4141"
echo "- MailHog: http://localhost:8025"
echo "- SonarQube: http://localhost:9000"
EOF
    chmod +x scripts/start-dev.sh
    
    # Create stop script
    cat > scripts/stop-dev.sh << 'EOF'
#!/bin/bash
# Stop development environment
set -euo pipefail

# Determine compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

echo "Stopping IDP development environment..."
$COMPOSE_CMD down

echo "Development environment stopped."
EOF
    chmod +x scripts/stop-dev.sh
    
    # Create reset script
    cat > scripts/reset-dev.sh << 'EOF'
#!/bin/bash
# Reset development environment (removes all data)
set -euo pipefail

# Determine compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

read -p "This will remove all development data. Are you sure? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Resetting IDP development environment..."
    $COMPOSE_CMD down -v --remove-orphans
    docker system prune -f
    echo "Development environment reset complete."
else
    echo "Reset cancelled."
fi
EOF
    chmod +x scripts/reset-dev.sh
    
    # Create logs script
    cat > scripts/logs-dev.sh << 'EOF'
#!/bin/bash
# View development environment logs
set -euo pipefail

# Determine compose command
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

SERVICE=${1:-}

if [[ -n "$SERVICE" ]]; then
    echo "Following logs for service: $SERVICE"
    $COMPOSE_CMD logs -f "$SERVICE"
else
    echo "Following logs for all services..."
    $COMPOSE_CMD logs -f
fi
EOF
    chmod +x scripts/logs-dev.sh
    
    log_success "Created development helper scripts"
}

main() {
    log_info "Setting up IDP development environment..."
    
    check_prerequisites
    create_env_files
    create_monitoring_configs
    create_database_init_script
    setup_development_scripts
    
    log_success "Development environment setup complete!"
    echo
    log_info "To start the development environment, run:"
    echo "  ./scripts/start-dev.sh"
    echo
    log_info "To stop the development environment, run:"
    echo "  ./scripts/stop-dev.sh"
    echo
    log_info "To view logs, run:"
    echo "  ./scripts/logs-dev.sh [service-name]"
    echo
    log_info "To reset the development environment (removes all data), run:"
    echo "  ./scripts/reset-dev.sh"
}

# Run main function
main "$@"