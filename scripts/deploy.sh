#!/bin/bash
# ============================================================
# Metl Platform — Deploy Helper
# Run this from the metl-ops directory
# ============================================================
set -euo pipefail

COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$COMPOSE_DIR"

usage() {
    cat <<EOF
Metl Platform Deployment Helper

Usage: $0 <command> [options]

Commands:
  up        Start all services on this VM
  down      Stop all services on this VM
  restart   Restart all services
  pull      Pull latest images
  status    Show running containers
  logs      Show logs (use: $0 logs <service>)
  backup    Run database backup
  update    Pull and restart all services
  health    Run health checks

VM-Specific Commands:
  up-data    Start data stack (VM-2)
  up-app     Start app stack (VM-1)
  up-ai      Start AI stack (VM-3)

Examples:
  $0 up-app
  $0 update
  $0 logs control-plane
  $0 backup
EOF
    exit 1
}

cmd="${1:-}"
service="${2:-}"

up_data() {
    echo "=== Starting Data Stack ==="
    docker compose -f docker-compose.data.yml up -d
}

up_app() {
    echo "=== Starting App Stack ==="
    touch traefik/acme.json
    chmod 600 traefik/acme.json
    docker compose -f docker-compose.app.yml up -d
}

up_ai() {
    echo "=== Starting AI Stack ==="
    docker compose -f docker-compose.ai.yml up -d
}

down_all() {
    echo "=== Stopping all stacks ==="
    docker compose -f docker-compose.data.yml down 2>/dev/null || true
    docker compose -f docker-compose.app.yml down 2>/dev/null || true
    docker compose -f docker-compose.ai.yml down 2>/dev/null || true
}

pull_all() {
    echo "=== Pulling latest images ==="
    docker compose -f docker-compose.data.yml pull 2>/dev/null || true
    docker compose -f docker-compose.app.yml pull 2>/dev/null || true
    docker compose -f docker-compose.ai.yml pull 2>/dev/null || true
}

update() {
    echo "=== Updating all services ==="
    pull_all
    up_app
    up_ai
    up_data
    echo "=== Cleaning up old images ==="
    docker image prune -af --filter "until=168h" || true
}

show_status() {
    echo "=== Running Containers ==="
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

show_logs() {
    if [[ -z "$service" ]]; then
        echo "Usage: $0 logs <service_name>"
        docker ps --format "table {{.Names}}"
        exit 1
    fi
    docker logs -f --tail 100 "$service"
}

run_backup() {
    echo "=== Running Database Backup ==="
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_DIR="./backups"
    mkdir -p "$BACKUP_DIR"

    # PostgreSQL backup via docker exec
    if docker ps --format '{{.Names}}' | grep -q "metl-postgres"; then
        docker exec metl-postgres pg_dump -U "${POSTGRES_USER:-metl_prod_admin}" "${POSTGRES_DB:-metl}" | gzip > "$BACKUP_DIR/metl_${TIMESTAMP}.sql.gz"
        echo "Backup saved: $BACKUP_DIR/metl_${TIMESTAMP}.sql.gz"
    else
        echo "PostgreSQL container not found. Is the data stack running?"
    fi
}

health_check() {
    echo "=== Running Health Checks ==="

    # Data Server services
    echo "--- Data Server ---"
    curl -sf http://localhost:5432 2>/dev/null && echo "PostgreSQL: OK" || echo "PostgreSQL: CHECK"
    curl -sf http://localhost:6379 2>/dev/null && echo "Redis: OK" || echo "Redis: CHECK"
    curl -sf http://localhost:8222/healthz 2>/dev/null && echo "NATS: OK" || echo "NATS: CHECK"
    curl -sf http://localhost:9000/api/system/status 2>/dev/null && echo "SonarQube: OK" || echo "SonarQube: CHECK"

    # App Server services
    echo "--- App Server ---"
    curl -sf http://localhost:3001/api/health 2>/dev/null && echo "Control-Plane: OK" || echo "Control-Plane: CHECK"
    curl -sf http://localhost:3002/health 2>/dev/null && echo "Simple-Vault: OK" || echo "Simple-Vault: CHECK"

    # AI Worker
    echo "--- AI Worker ---"
    curl -sf http://localhost:8000/health 2>/dev/null && echo "Vibe-Coder: OK" || echo "Vibe-Coder: CHECK"

    # Traefik
    echo "--- Traefik ---"
    curl -sf http://localhost:8080/ping 2>/dev/null && echo "Traefik: OK" || echo "Traefik: CHECK"
}

case "$cmd" in
    up|start)
        up_app && up_ai && up_data
        ;;
    up-data)
        up_data
        ;;
    up-app)
        up_app
        ;;
    up-ai)
        up_ai
        ;;
    down|stop)
        down_all
        ;;
    restart)
        down_all
        up_app && up_ai && up_data
        ;;
    pull)
        pull_all
        ;;
    update)
        update
        ;;
    status|ps)
        show_status
        ;;
    logs)
        show_logs
        ;;
    backup)
        run_backup
        ;;
    health)
        health_check
        ;;
    *)
        usage
        ;;
esac
