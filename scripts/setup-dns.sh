#!/bin/bash
# ============================================================
# Metl Platform — Cloudflare DNS Setup
# Run this after getting your Azure VM public IPs
# Requires: curl, jq
# ============================================================
set -euo pipefail

# Configuration - FILL THESE IN
CF_API_TOKEN="your-cloudflare-api-token"
CF_ZONE_ID="your-zone-id-for-metl-run"
VM1_PUBLIC_IP="YOUR_VM1_PUBLIC_IP"
VM1_PRIVATE_IP="YOUR_VM1_PRIVATE_IP"

ZONE_ID="$CF_ZONE_ID"
API_TOKEN="$CF_API_TOKEN"
API_BASE="https://api.cloudflare.com/client/v4"

headers=(-H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json")

create_record() {
    local name="$1"
    local type="$2"
    local content="$3"
    local proxied="${4:-false}"
    local ttl="${5:-1}"

    echo "Creating $type record: $name -> $content (proxied=$proxied)"

    curl -s -X POST "${API_BASE}/zones/${ZONE_ID}/dns_records" \
        "${headers[@]}" \
        -d "{
            \"type\": \"$type\",
            \"name\": \"$name\",
            \"content\": \"$content\",
            \"ttl\": $ttl,
            \"proxied\": $proxied
        }" | jq -r '.success, .errors'
}

echo "================================================================"
echo "  Metl Platform — Cloudflare DNS Setup"
echo "================================================================"
echo ""
echo "Domain: metl.run"
echo "VM-1 Public IP: $VM1_PUBLIC_IP"
echo ""
read -p "Continue? (y/N): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0

# Delete existing A records for metl.run (optional - be careful)
echo ""
echo "=== Fetching existing DNS records ==="
EXISTING=$(curl -s "${API_BASE}/zones/${ZONE_ID}/dns_records?type=A" "${headers[@]}")
echo "Existing A records:"
echo "$EXISTING" | jq -r '.result[] | "  \(.name) -> \(.content)"'

echo ""
echo "=== Creating DNS records ==="

# Main domain
create_record "metl.run" "A" "$VM1_PUBLIC_IP" "true"
create_record "www.metl.run" "A" "$VM1_PUBLIC_IP" "true"

# Optional: Status page subdomain (can point to UptimeRobot or similar)
# create_record "status.metl.run" "CNAME" "stats.uptimerobot.com" "true"

echo ""
echo "=== DNS Setup Complete ==="
echo ""
echo "IMPORTANT: In Cloudflare dashboard, configure these settings:"
echo "  1. SSL/TLS mode: Full (Strict)"
echo "  2. Always Use HTTPS: ON"
echo "  3. Auto Minify: JS, CSS, HTML"
echo "  4. Brotli: ON"
echo "  5. Security Level: Medium"
echo ""
echo "It may take a few minutes for DNS to propagate."
echo "Verify: nslookup metl.run"
