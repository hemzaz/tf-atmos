# Start Development Environment

Start the local Docker-based development environment for platform development and testing.

## What this provides
- 🐳 Backstage IDP platform running locally
- 📊 Grafana dashboards for monitoring
- 🔍 Prometheus metrics collection
- 📧 MailHog for email testing
- 🐘 PostgreSQL database
- 🔴 Redis for caching
- 📝 SonarQube for code quality (optional)

## Prerequisites
- Docker and Docker Compose installed
- At least 8GB RAM available for Docker
- Ports 3000, 8000, 3001, 9090, 4141, 8025 available

## Commands to run

### Start development environment
```bash
make dev-start
```

### Alternative startup methods
```bash
# Using script directly
./scripts/start-dev.sh

# Using Docker Compose
docker-compose up -d

# Start with monitoring stack
docker-compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d
```

## Services and ports
After startup, these services will be available:

| Service | URL | Purpose |
|---------|-----|---------|
| Backstage IDP | http://localhost:3000 | Developer portal and catalog |
| Platform API | http://localhost:8000 | Backend API services |
| Grafana | http://localhost:3001 | Monitoring dashboards (admin/admin_dev) |
| Prometheus | http://localhost:9090 | Metrics collection |
| Atlantis | http://localhost:4141 | Terraform PR automation |
| MailHog | http://localhost:8025 | Email testing |
| SonarQube | http://localhost:9000 | Code quality analysis |

## Startup process
1. **Pull images** - Downloads latest container images
2. **Build services** - Builds any custom containers
3. **Start dependencies** - Database, Redis, etc.
4. **Start applications** - Backstage, APIs, monitoring
5. **Health checks** - Verifies all services are ready

## Verification steps
```bash
# Check all services are running
make dev-logs

# Or check specific service
docker-compose ps

# Test service endpoints
curl http://localhost:3000/api/health
curl http://localhost:8000/health
```

## Viewing logs
```bash
# Follow all logs
make dev-logs

# Follow specific service logs
make dev-logs backstage
make dev-logs platform-api

# Using Docker Compose directly
docker-compose logs -f
docker-compose logs -f backstage
```

## Development workflow
1. **Start environment**: `make dev-start`
2. **Make changes** to code or configurations
3. **Hot reload** - Most services auto-reload on changes
4. **Test changes** via web interfaces or APIs
5. **View logs** to debug issues: `make dev-logs`
6. **Stop when done**: `make dev-stop`

## Customization

### Environment variables
Edit `.env` file to customize:
```bash
# GitHub integration
GITHUB_TOKEN=your_token_here
AUTH_GITHUB_CLIENT_ID=your_client_id
AUTH_GITHUB_CLIENT_SECRET=your_client_secret

# AWS settings
AWS_DEFAULT_REGION=us-west-2
AWS_PROFILE=development

# Feature flags
ENABLE_MONITORING=true
ENABLE_SECURITY_SCANNING=true
```

### Override configurations
Create `docker-compose.override.yml` for local customizations:
```yaml
version: '3.8'
services:
  backstage:
    volumes:
      - ./local-config:/app/local-config
    environment:
      - DEBUG=true
```

## Troubleshooting

### Common issues

**Port conflicts:**
```bash
# Check what's using a port
lsof -i :3000
# Kill processes if needed
sudo lsof -t -i:3000 | xargs kill -9
```

**Out of memory:**
- Increase Docker memory limit to 8GB+
- Close unused applications
- Consider disabling some services in docker-compose.yml

**Services not starting:**
```bash
# Check logs for specific service
docker-compose logs backstage

# Restart specific service
docker-compose restart backstage

# Full restart
make dev-stop && make dev-start
```

**Database connection issues:**
```bash
# Reset database
docker-compose down -v
make dev-start
```

## Stopping the environment
```bash
# Stop all services
make dev-stop

# Stop and remove volumes (full reset)
make dev-reset
```

## Advanced usage

### Production-like testing
```bash
# Start with production configs
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Performance testing
```bash
# Start with monitoring enabled
make dev-start
# Open Grafana at http://localhost:3001
# Load test your changes
# Monitor performance metrics
```