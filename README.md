# Metl Operations

Production deployment configurations for the Metl platform on Azure VPS.

## Architecture

Single domain (`metl.run`) unified platform with path-based routing across 3 Azure VMs.

| VM | Role | Services |
|---|---|---|
| VM-1 | App Server | Traefik, Next.js Frontend, Control-Plane, 9 platform services, AI agents, Security Scanner |
| VM-2 | Data Server | PostgreSQL, Redis, NATS JetStream, SonarQube, Prometheus, Grafana |
| VM-3 | AI Worker | Vibe-Coder, Vibe-Coder-SDK |

## Quick Start

1. Copy env template and fill in values:
```bash
cp .env.example .env
# Edit .env with your credentials
```

2. Deploy VM-2 (Data) first:
```bash
ssh metladmin@<VM2_IP>
cd ~/metl-ops
docker-compose -f docker-compose.data.yml up -d
```

3. Deploy VM-3 (AI Worker):
```bash
ssh metladmin@<VM3_IP>
cd ~/metl-ops
docker-compose -f docker-compose.ai.yml up -d
```

4. Deploy VM-1 (App Server) last:
```bash
ssh metladmin@<VM1_IP>
cd ~/metl-ops
docker-compose -f docker-compose.app.yml up -d
```

## Directory Structure

```
metl-ops/
├── docker-compose.app.yml    # VM-1: All app services
├── docker-compose.data.yml   # VM-2: Data infrastructure
├── docker-compose.ai.yml     # VM-3: AI worker agents
├── .env.example              # Environment variable template
├── traefik/
│   ├── traefik.yml           # Traefik main config
│   └── dynamic/
│       └── middlewares.yml   # Rate limiting, auth, security headers
├── monitoring/
│   ├── prometheus.yml
│   └── grafana/
│       ├── provisioning/
│       └── dashboards/
├── scripts/
│   └── deploy.sh             # Deployment helper
└── backups/
    └── pgbackup/
```

## GitHub Actions

CI/CD workflows are in each service repository under `.github/workflows/`.
Updates to `main` branch automatically build and deploy to the correct VM.

## Networking

All VMs communicate over an Azure Virtual Network. VM-2 has no public IP.
Only VM-1 (Traefik on 80/443) is public-facing.

## DNS

One A record: `metl.run` -> VM-1 Public IP

All features are paths:
- `metl.run/` - Dashboard
- `metl.run/vault` - Simple Vault
- `metl.run/api/*` - API Gateway
