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
