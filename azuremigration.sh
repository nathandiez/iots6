#!/usr/bin/env bash
# iot_azure_migration.sh - Script to create Azure Terraform files for IoT infrastructure migration
set -e

echo "Creating Azure migration files for IoT infrastructure..."

# Create terraform directory if it doesn't exist
mkdir -p terraform

# Create main.tf
cat > terraform/main.tf << 'EOF'
# Azure Provider configuration
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

# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-iot-infrastructure"
  location = var.location
  tags     = var.tags
}

# Create virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-iot"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}

# Create subnet
resource "azurerm_subnet" "subnet" {
  name                 = "subnet-iot"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create public IP
resource "azurerm_public_ip" "public_ip" {
  name                = "pip-iot"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "nediots"
  tags                = var.tags
}

# Create Network Security Group
resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-iot"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  # Allow SSH
  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP/8080 for web services
  security_rule {
    name                       = "HTTP-8080"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow MQTT (1883)
  security_rule {
    name                       = "MQTT"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1883"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow MQTT over WebSockets (9001)
  security_rule {
    name                       = "MQTT-WS"
    priority                   = 1004
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9001"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow PostgreSQL (5432)
  security_rule {
    name                       = "PostgreSQL"
    priority                   = 1005
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Create network interface
resource "azurerm_network_interface" "nic" {
  name                = "nic-iot"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Connect NSG to NIC
resource "azurerm_network_interface_security_group_association" "nsg_assoc" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Create virtual machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-nediots"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.ssh_username
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]
  tags = var.tags

  admin_ssh_key {
    username   = var.ssh_username
    public_key = file(var.ssh_public_key_path)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = var.disk_size
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts"
    version   = "latest"
  }

  custom_data = base64encode(<<-EOT
#!/bin/bash
apt-get update
apt-get install -y avahi-daemon
# Set hostname
hostnamectl set-hostname nediots
# Configure avahi
mkdir -p /etc/avahi/avahi-daemon.conf.d
cat > /etc/avahi/avahi-daemon.conf.d/10-hostname.conf << 'EOL'
[server]
host-name=nediots

[publish]
publish-hinfo=yes
publish-workstation=yes
EOL

# Disable IPv6 in Avahi for better stability
sed -i 's/^use-ipv6=.*/use-ipv6=no/' /etc/avahi/avahi-daemon.conf

systemctl restart avahi-daemon
systemctl enable avahi-daemon
EOT
  )
}
EOF

# Create variables.tf
cat > terraform/variables.tf << 'EOF'
variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_B2s"  # 2 vCPUs, 4 GB RAM - good for IoT services
}

variable "tags" {
  description = "Tags to apply to the resources"
  type        = map(string)
  default     = {
    "Environment" = "Development"
    "Project"     = "IoT"
    "ManagedBy"   = "Terraform"
  }
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 30
}

variable "ssh_username" {
  description = "Username for SSH access"
  type        = string
  default     = "nathan"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"  # Use RSA keys with Azure
}
EOF

# Create outputs.tf
cat > terraform/outputs.tf << 'EOF'
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "vm_id" {
  description = "ID of the created VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "vm_name" {
  description = "Name of the VM"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "private_ip" {
  description = "Private IP address of the VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.public_ip.ip_address
}

output "server_ip" {
  description = "Primary IP address (kept for compatibility with existing scripts)"
  value       = azurerm_public_ip.public_ip.ip_address
}

output "vm_ip_addresses" {
  description = "IP addresses of the VM (for compatibility with existing scripts)"
  value       = {
    nediots = { "0" = [azurerm_public_ip.public_ip.ip_address] }
  }
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = azurerm_public_ip.public_ip.fqdn
}
EOF

# Create .gitignore for Terraform
cat > terraform/.gitignore << 'EOF'
# Local .terraform directories
**/.terraform/*

# .tfstate files
*.tfstate
*.tfstate.*

# Crash log files
crash.log
crash.*.log

# Exclude all .tfvars files
*.tfvars
*.tfvars.json

# Ignore override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Ignore CLI configuration files
.terraformrc
terraform.rc

# Ignore lock files
.terraform.lock.hcl

# Ignore Azure credentials
credentials.tfrc.json
EOF

# Create Azure environment setup script
cat > set-azure-env.sh << 'EOF'
#!/usr/bin/env bash
# set-azure-env.sh - Configure Azure authentication for Terraform

# Choose one of the authentication methods below:

# Method 1: Service Principal Authentication (recommended for automation)
# export ARM_CLIENT_ID="00000000-0000-0000-0000-000000000000"
# export ARM_CLIENT_SECRET="your-client-secret"
# export ARM_TENANT_ID="00000000-0000-0000-0000-000000000000"
# export ARM_SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"

# Method 2: Azure CLI Authentication (easier for development)
# Requires running 'az login' first
echo "Using Azure CLI authentication for Terraform."
echo "If not logged in, please run: az login"

# Optional: Select a specific subscription
# az account set --subscription "Your Subscription Name"

echo "✅ Azure Terraform environment configured."
EOF

# Make the script executable
chmod +x set-azure-env.sh

# Create updated deploy script
cat > deploy.sh << 'EOF'
#!/usr/bin/env bash
# deploy.sh - Deployment script for IoT infrastructure on Azure
set -e

# Configuration
TARGET_HOSTNAME="nediots"

# Check for --nuke flag
if [[ "$1" == "--nuke" ]]; then
  NUKE_MODE=true
  echo "Flag --nuke detected: Will recreate VM before configuring"
else
  NUKE_MODE=false
  echo "No --nuke flag: Will only configure the existing VM"
fi

# Source Azure environment variables
source ./set-azure-env.sh

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Run Terraform if in nuke mode
if [ "$NUKE_MODE" = true ]; then
  echo "Starting with a clean slate..."
  # Don't delete tfstate when using Azure - it helps with cleanup
  # rm -f terraform.tfstate terraform.tfstate.backup
  
  echo "Initializing Terraform..."
  terraform init
  
  echo "Creating new VM in Azure..."
  terraform apply -auto-approve
fi

# Get the IP address using terraform output
echo "Getting VM public IP address..."
# Retry a few times because IP might not be immediately available after VM creation
for i in {1..10}; do
  IP=$(terraform output -raw public_ip 2>/dev/null || echo "")
  
  if [ -n "$IP" ] && [ "$IP" != "null" ]; then
    echo "Found IP: $IP"
    break
  fi
  
  echo "Waiting for IP address to be assigned... (attempt $i)"
  sleep 15
  terraform refresh > /dev/null 2>&1
done

# Validate IP address
if [ -z "$IP" ] || [ "$IP" == "null" ]; then
  echo "Error: Could not retrieve a valid IP address for $TARGET_HOSTNAME."
  echo "You may need to check the Azure portal or run terraform refresh."
  exit 1
fi

echo "VM IP address: $IP"

# Update Ansible inventory
cd ../ansible
sed -i.bak "s/ansible_host=.*/ansible_host=$IP/" inventory/hosts

# Wait for SSH to become available
echo "Waiting for SSH to become available..."
MAX_SSH_WAIT=300 # 5 minutes
START_TIME=$(date +%s)

while true; do
  if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 nathan@"$IP" echo ready 2>/dev/null; then
    echo "SSH is available!"
    break
  fi
  
  # Check if we've waited too long
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
  
  if [ $ELAPSED_TIME -gt $MAX_SSH_WAIT ]; then
    echo "Timed out waiting for SSH. You may need to check the VM console in Azure portal."
    exit 1
  fi
  
  echo "Still waiting for SSH..."
  sleep 10
done

# Run Ansible playbook
echo "Running Ansible to configure the server..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/main.yml

echo "Deployment complete! Server is now running at http://$IP:8080"
echo "FQDN: $(cd ../terraform && terraform output -raw fqdn 2>/dev/null || echo "Not available")"
EOF

# Create updated TimescaleDB deployment script
cat > tsdeploy.sh << 'EOF'
#!/usr/bin/env bash
set -e

IP=${1:-$(terraform -chdir=terraform output -json vm_ip_addresses | jq -r '.nediots | .[][] | select(. != "127.0.0.1")' | head -n 1)}

if [ -z "$IP" ] || [ "$IP" == "null" ]; then
  echo "Error: No valid IP address. Provide IP as argument."
  exit 1
fi

echo "Deploying TS to $IP"

mkdir -p ansible/inventory
cat > ansible/inventory/hosts << EOFHOSTS
[iot_servers]
nediots ansible_host=$IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOFHOSTS

cd ansible
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/timescaledb.yml

echo "TimescaleDB deployment completed!"
EOF

# Create IoT service deployment script
cat > iotdeploy.sh << 'EOF'
#!/usr/bin/env bash
set -e

IP=${1:-$(terraform -chdir=terraform output -json vm_ip_addresses | jq -r '.nediots | .[][] | select(. != "127.0.0.1")' | head -n 1)}

if [ -z "$IP" ] || [ "$IP" == "null" ]; then
  echo "Error: No valid IP address. Provide IP as argument."
  exit 1
fi

echo "Deploying IoT Service to $IP"

mkdir -p ansible/inventory
cat > ansible/inventory/hosts << EOFHOSTS
[iot_servers]
nediots ansible_host=$IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOFHOSTS

cd ansible
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook playbooks/iot_service.yml

echo "IoT Service deployment completed!"
EOF

# Create main.tf in the root directory
cat > main.tf << 'EOF'
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Reference to the terraform module
module "iot_infrastructure" {
  source = "./terraform"
}

output "server_ip" {
  value = module.iot_infrastructure.public_ip
}

output "vm_ip_addresses" {
  value = module.iot_infrastructure.vm_ip_addresses
}
EOF

# Make scripts executable
chmod +x deploy.sh
chmod +x tsdeploy.sh
chmod +x iotdeploy.sh

echo "Azure migration files created successfully!"
echo ""
echo "Next steps:"
echo "1. Install Azure CLI if not already installed: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
echo "2. Run: az login"
echo "3. Run: ./deploy.sh --nuke to create and configure the VM"
echo "4. Your existing Ansible playbooks will be used as-is"
echo ""
echo "Note: The original Proxmox files are stored in the 'proxmox_stuff' directory"