#!/usr/bin/env bash
# setup-persistent-ip-only.sh - Just create the persistent IP resource

set -e

echo "=== Setting up Persistent IP for IoT Infrastructure ==="
echo ""

# Source Azure environment variables
source ./set-azure-env.sh

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Create temporary Terraform config to create just the persistent IP
cat > main.tf << 'EOL'
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create the persistent public IP in the existing resource group
resource "azurerm_public_ip" "persistent_ip" {
  name                = "ned-iot-persistent"
  location            = "eastus"
  resource_group_name = "rg-persistent-resources"
  allocation_method   = "Static"
  domain_name_label   = "nediots-persist"
  sku                 = "Standard"
  
  tags = {
    "Environment" = "Production"
    "ManagedBy"   = "Terraform"
    "Purpose"     = "IoT Infrastructure"
  }
}

output "persistent_ip_address" {
  value = azurerm_public_ip.persistent_ip.ip_address
}

output "persistent_fqdn" {
  value = azurerm_public_ip.persistent_ip.fqdn
}
EOL

# Initialize and apply Terraform to create the persistent IP
echo "Creating persistent IP resource..."
terraform init -input=false
terraform apply -auto-approve

# Capture the outputs
PERSISTENT_IP=$(terraform output -raw persistent_ip_address)
PERSISTENT_FQDN=$(terraform output -raw persistent_fqdn)

# Return to the original directory
cd - > /dev/null

echo "✅ Persistent IP created successfully!"
echo "IP Address: $PERSISTENT_IP"
echo "FQDN: $PERSISTENT_FQDN"
echo ""

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

echo "Now your persistent IP is ready to use with your IoT infrastructure."
echo "The IP will remain even when you destroy and recreate the VM."
echo ""
echo "Run your deploy script with: ./deploy.sh --nuke"