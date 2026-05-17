#!/bin/bash
# ============================================================
# Metl Local Build & Deploy Script
# Run this ON THE SERVER after copying metl-platform source
# ============================================================
set -euo pipefail

METL_PLATFORM_DIR="${1:-$HOME/metl-platform}"

echo "============================================================"
echo "  Metl Platform — Local Docker Image Build"
echo "============================================================"
echo ""

if [[ ! -d "$METL_PLATFORM_DIR" ]]; then
    echo "ERROR: metl-platform source not found at $METL_PLATFORM_DIR"
    echo "Copy it from your Mac first:"
    echo "  scp -r ./metl-platform metladmin@<VM-1-IP>:~/"
    exit 1
fi

cd "$METL_PLATFORM_DIR"

# Tag prefix (uses local names, not GHCR)
TAG_PREFIX="metl-local"

build_image() {
    local name="$1"
    local dockerfile_path="$2"
    local context="$3"
    
    echo ""
    echo "=== Building $name ==="
    docker build \
        -t "${TAG_PREFIX}/${name}:latest" \
        -f "$dockerfile_path" \
        "$context"
}

# Build all platform services
echo "=== Building Platform Services ==="
build_image "frontend"           "frontend/Dockerfile"           "frontend"
build_image "control-plane"      "services/control-plane/Dockerfile"      "services/control-plane"
build_image "orchestration-agent" "services/orchestration-agent/Dockerfile" "services/orchestration-agent"
build_image "resource-allocator" "services/resource-allocator/Dockerfile" "services/resource-allocator"
build_image "deployment-engine"  "services/deployment-engine/Dockerfile"  "services/deployment-engine"
build_image "sre-agent"          "services/sre-agent/Dockerfile"          "services/sre-agent"
build_image "eco-mode"           "services/eco-mode/Dockerfile"           "services/eco-mode"
build_image "scaling-agent"      "services/scaling-agent/Dockerfile"      "services/scaling-agent"
build_image "simple-vault"       "services/simple-vault/Dockerfile"       "services/simple-vault"

# Build agents
echo ""
echo "=== Building AI Agents ==="
build_image "vibe-coder"         "agents/vibe-coder/Dockerfile"           "agents/vibe-coder"
build_image "vibe-coder-sdk"     "agents/vibe-coder-sdk/Dockerfile"       "agents/vibe-coder-sdk"
build_image "security-hunter"    "agents/security-hunter/Dockerfile"      "agents/security-hunter"

echo ""
echo "=== Build complete ==="
echo ""
echo "Next: cd ~/metl-ops && docker compose -f docker-compose.app.local.yml up -d"
