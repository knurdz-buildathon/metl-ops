#!/bin/bash
# ============================================================
# Metl Platform — Azure VM Provisioning Script
# Run this on your LOCAL MACHINE with Azure CLI installed
# ============================================================
set -euo pipefail

# Configuration
RESOURCE_GROUP="metl-production"
LOCATION="eastus2"
VNET_NAME="metl-vnet"
VNET_PREFIX="10.0.0.0/16"
SUBNET_NAME="metl-subnet"
SUBNET_PREFIX="10.0.1.0/24"
NSG_NAME="metl-nsg"
SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

# VM Names
VM_APP="metl-app-server"
VM_DATA="metl-data-server"
VM_AI="metl-ai-worker"

# VM Sizes (change these if your region has capacity restrictions)
# Common alternatives: D*s_v3 (widely available), D*s_v5, D*s_v4, D*s_v6
# Check available sizes: az vm list-skus --location eastus2 --size "Standard_D*"
VM_APP_SIZE="Standard_D8s_v3"     # 8 vCPUs, 32 GB RAM
VM_DATA_SIZE="Standard_D4s_v3"    # 4 vCPUs, 16 GB RAM
VM_AI_SIZE="Standard_D8s_v3"      # 8 vCPUs, 32 GB RAM

# Check prerequisites
command -v az >/dev/null 2>&1 || { echo "Azure CLI not found. Install: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"; exit 1; }

# Check if logged in
az account show >/dev/null 2>&1 || { echo "Please login first: az login"; exit 1; }

echo "================================================================"
echo "  Metl Platform — Azure Infrastructure Provisioning"
echo "================================================================"
echo ""
echo "This will create:"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Virtual Network with subnet"
echo "  - Network Security Group"
echo "  - 3 VMs: $VM_APP, $VM_DATA, $VM_AI"
echo ""
read -p "Continue? (y/N): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && exit 0

# Generate SSH key if not exists
if [[ ! -f "$HOME/.ssh/id_rsa.pub" ]]; then
    echo "=== Generating SSH key ==="
    ssh-keygen -t rsa -b 4096 -f "$HOME/.ssh/id_rsa" -N ""
fi
SSH_KEY=$(cat "$SSH_KEY_PATH")

# Create Resource Group (reuse if exists)
echo "=== Creating Resource Group ==="
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    EXISTING_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    echo "Resource group '$RESOURCE_GROUP' already exists in '$EXISTING_LOCATION'. Reusing it."
    LOCATION="$EXISTING_LOCATION"
else
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags project=metl environment=production
fi

# Create Virtual Network (reuse if exists)
echo "=== Creating Virtual Network ==="
if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &>/dev/null; then
    echo "Virtual network '$VNET_NAME' already exists. Reusing it."
else
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "$VNET_PREFIX" \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix "$SUBNET_PREFIX" \
        --location "$LOCATION"
fi

# Create Network Security Group (reuse if exists)
echo "=== Creating Network Security Group ==="
if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME" &>/dev/null; then
    echo "NSG '$NSG_NAME' already exists. Reusing it."
else
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --location "$LOCATION"
fi

# NSG Rules
echo "=== Configuring NSG Rules ==="
# SSH
if az network nsg rule show --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" --name "Allow-SSH" &>/dev/null; then
    echo "NSG rule 'Allow-SSH' already exists. Skipping."
else
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-SSH" \
        --protocol Tcp \
        --priority 1000 \
        --destination-port-ranges 22 \
        --access Allow \
        --direction Inbound
fi

# HTTP
if az network nsg rule show --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" --name "Allow-HTTP" &>/dev/null; then
    echo "NSG rule 'Allow-HTTP' already exists. Skipping."
else
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-HTTP" \
        --protocol Tcp \
        --priority 1010 \
        --destination-port-ranges 80 \
        --access Allow \
        --direction Inbound
fi

# HTTPS
if az network nsg rule show --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" --name "Allow-HTTPS" &>/dev/null; then
    echo "NSG rule 'Allow-HTTPS' already exists. Skipping."
else
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-HTTPS" \
        --protocol Tcp \
        --priority 1020 \
        --destination-port-ranges 443 \
        --access Allow \
        --direction Inbound
fi

# Traefik Dashboard (restrict this to your IP in production)
if az network nsg rule show --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" --name "Allow-Traefik-Dashboard" &>/dev/null; then
    echo "NSG rule 'Allow-Traefik-Dashboard' already exists. Skipping."
else
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "Allow-Traefik-Dashboard" \
        --protocol Tcp \
        --priority 1030 \
        --destination-port-ranges 8080 \
        --access Allow \
        --direction Inbound
fi

# VM-1: App Server
echo "=== Creating VM-1: App Server ($VM_APP) ==="
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_APP" &>/dev/null; then
    echo "VM '$VM_APP' already exists. Skipping."
else
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_APP" \
        --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
        --size "$VM_APP_SIZE" \
        --admin-username "metladmin" \
        --ssh-key-values "$SSH_KEY_PATH" \
        --os-disk-size-gb 128 \
        --storage-sku "Premium_LRS" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --nsg "$NSG_NAME" \
        --public-ip-sku Standard \
        --location "$LOCATION" \
        --tags role=app-server project=metl
fi

# VM-2: Data Server (NO public IP)
echo "=== Creating VM-2: Data Server ($VM_DATA) ==="
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_DATA" &>/dev/null; then
    echo "VM '$VM_DATA' already exists. Skipping."
else
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_DATA" \
        --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
        --size "$VM_DATA_SIZE" \
        --admin-username "metladmin" \
        --ssh-key-values "$SSH_KEY_PATH" \
        --os-disk-size-gb 256 \
        --storage-sku "Premium_LRS" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --nsg "$NSG_NAME" \
        --public-ip-address "" \
        --location "$LOCATION" \
        --tags role=data-server project=metl
fi

# VM-3: AI Worker
echo "=== Creating VM-3: AI Worker ($VM_AI) ==="
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_AI" &>/dev/null; then
    echo "VM '$VM_AI' already exists. Skipping."
else
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_AI" \
        --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
        --size "$VM_AI_SIZE" \
        --admin-username "metladmin" \
        --ssh-key-values "$SSH_KEY_PATH" \
        --os-disk-size-gb 128 \
        --storage-sku "Premium_LRS" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --nsg "$NSG_NAME" \
        --public-ip-sku Standard \
        --location "$LOCATION" \
        --tags role=ai-worker project=metl
fi

# Get IPs
echo ""
echo "=== VM Details ==="
echo ""
APP_PUBLIC_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_APP" --show-details --query publicIps -o tsv)
APP_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_APP" --show-details --query privateIps -o tsv)
DATA_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_DATA" --show-details --query privateIps -o tsv)
AI_PUBLIC_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_AI" --show-details --query publicIps -o tsv)
AI_PRIVATE_IP=$(az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_AI" --show-details --query privateIps -o tsv)

echo "VM-1 (App Server):"
echo "  Public IP:  $APP_PUBLIC_IP"
echo "  Private IP: $APP_PRIVATE_IP"
echo ""
echo "VM-2 (Data Server):"
echo "  Public IP:  (none — private only)"
echo "  Private IP: $DATA_PRIVATE_IP"
echo ""
echo "VM-3 (AI Worker):"
echo "  Public IP:  $AI_PUBLIC_IP"
echo "  Private IP: $AI_PRIVATE_IP"
echo ""

# Save to file for reference
cat > "./azure-infrastructure.json" <<EOF
{
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "vnet_name": "$VNET_NAME",
  "vms": {
    "app_server": {
      "name": "$VM_APP",
      "public_ip": "$APP_PUBLIC_IP",
      "private_ip": "$APP_PRIVATE_IP"
    },
    "data_server": {
      "name": "$VM_DATA",
      "public_ip": null,
      "private_ip": "$DATA_PRIVATE_IP"
    },
    "ai_worker": {
      "name": "$VM_AI",
      "public_ip": "$AI_PUBLIC_IP",
      "private_ip": "$AI_PRIVATE_IP"
    }
  }
}
EOF

echo "=== Infrastructure details saved to azure-infrastructure.json ==="
echo ""
echo "Next steps:"
echo "  1. Set DNS A record: metl.run -> $APP_PUBLIC_IP"
echo "  2. SSH into VMs and run bootstrap: ./scripts/bootstrap-vm.sh"
echo "  3. Copy .env file and start services"
