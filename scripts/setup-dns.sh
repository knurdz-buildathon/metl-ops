#!/bin/bash
# ============================================================
# Metl Platform — Hostinger DNS Setup Helper
# Prints the exact DNS records to add in Hostinger hPanel
# ============================================================
set -euo pipefail

# Fill these in after running provision-azure.sh
VM1_PUBLIC_IP="YOUR_VM1_PUBLIC_IP"
VM3_PUBLIC_IP="YOUR_VM3_PUBLIC_IP"

echo "================================================================"
echo "  Metl Platform — Hostinger DNS Records"
echo "================================================================"
echo ""
echo "Domain: metl.run"
echo ""
echo "ADD THESE RECORDS in Hostinger hPanel:"
echo "  hpanel.hostinger.com → Domains → metl.run → DNS Records"
echo ""
echo "Step 1: Delete any existing A records for @, *, www, ai"
echo ""
echo "Step 2: Add these new A records:"
echo ""
printf "| %-5s | %-15s | %-20s | %-10s |\n" "Type" "Name" "Points to" "TTL"
printf "| %-5s | %-15s | %-20s | %-10s |\n" "-----" "---------------" "--------------------" "----------"
printf "| %-5s | %-15s | %-20s | %-10s |\n" "A" "@" "$VM1_PUBLIC_IP" "3600"
printf "| %-5s | %-15s | %-20s | %-10s |\n" "A" "*" "$VM1_PUBLIC_IP" "3600"
printf "| %-5s | %-15s | %-20s | %-10s |\n" "A" "www" "$VM1_PUBLIC_IP" "3600"
printf "| %-5s | %-15s | %-20s | %-10s |\n" "A" "ai" "$VM3_PUBLIC_IP" "3600"
echo ""
echo "Notes:"
echo "  - @     = root domain (metl.run)"
echo "  - *     = wildcard (covers app.metl.run, api.metl.run, etc.)"
echo "  - www   = www.metl.run"
echo "  - ai    = AI worker (ai.metl.run)"
echo ""
echo "Step 3: Keep Hostinger default nameservers (no changes needed)"
echo ""
echo "Step 4: Wait 5-60 minutes for DNS to propagate"
echo ""
echo "Verify:"
echo "  nslookup metl.run"
echo "  nslookup app.metl.run"
echo "  nslookup ai.metl.run"
echo ""
