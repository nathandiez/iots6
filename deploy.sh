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

# Verify persistent IP exists before doing anything else
echo "Verifying persistent IP exists..."
az network public-ip show --name ned-iot-persistent --resource-group rg-persistent-resources >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: Persistent IP 'ned-iot-persistent' not found in resource group 'rg-persistent-resources'"
  echo "Please run the setup-persistent-ip-only.sh script first."
  exit 1
fi
echo "✅ Persistent IP found, continuing with deployment"

# Change to terraform directory
cd "$(dirname "$0")/terraform"

# Get the current IP address for host key removal
CURRENT_IP=$(terraform output -raw public_ip 2>/dev/null || echo "")

# Run Terraform if in nuke mode
if [ "$NUKE_MODE" = true ]; then
  echo "Starting with a clean slate..."
  
  # Remove host key if we have a current IP
  if [ -n "$CURRENT_IP" ] && [ "$CURRENT_IP" != "null" ]; then
    echo "Removing SSH host key for $CURRENT_IP..."
    ssh-keygen -R "$CURRENT_IP"
  fi
  
  # Initialize Terraform first
  echo "Initializing Terraform..."
  terraform init
  
  # Destroy VM and related resources only - NEVER touch the resource group!
  echo "Removing previous VM resources..."
  
  # First destroy the VM since other resources depend on it
  terraform destroy -target="azurerm_linux_virtual_machine.vm" -auto-approve || true
  
  # Then destroy other resources in dependency order
  terraform destroy -target="azurerm_network_interface_security_group_association.nsg_assoc" -auto-approve || true
  terraform destroy -target="azurerm_network_interface.nic" -auto-approve || true
  terraform destroy -target="azurerm_network_security_group.nsg" -auto-approve || true
  terraform destroy -target="azurerm_subnet.subnet" -auto-approve || true
  terraform destroy -target="azurerm_virtual_network.vnet" -auto-approve || true
  terraform destroy -target="azurerm_public_ip.public_ip" -auto-approve || true
  
  # IMPORTANT: Never try to destroy the resource group or run a general destroy
  # without targets as it will hang trying to delete the resource group
  
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

echo "VM public IP: $IP"

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