#!/usr/bin/env bash
# deploy.sh - Main deployment script for iots6 project
# Usage:
#   ./deploy.sh                   (Configures existing VM using Ansible)
#   ./deploy.sh --nuke            (Destroys VM via Terraform, creates a new one, then configures with Ansible)
#   ./deploy.sh --service NAME    (Deploys only the specified service: mosquitto, timescaledb, iot_service, data_service)
set -e

# --- Configuration ---
# Set the base hostname for the target server (without .local)
TARGET_HOSTNAME="pxiots"
# --- End Configuration ---

# --- Process command line arguments ---
RUN_TERRAFORM_APPLY=false
SPECIFIC_SERVICE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --nuke)
      RUN_TERRAFORM_APPLY=true
      shift
      ;;
    --service)
      SPECIFIC_SERVICE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./deploy.sh [--nuke] [--service NAME]"
      exit 1
      ;;
  esac
done

# Log execution for debugging
echo "----------------------------------------"
echo "Executing deployment for iots6 project"
echo "Target hostname: ${TARGET_HOSTNAME}"
echo "Run Terraform: ${RUN_TERRAFORM_APPLY}"
if [ -n "$SPECIFIC_SERVICE" ]; then
  echo "Deploying specific service: ${SPECIFIC_SERVICE}"
else
  echo "Deploying all services"
fi
echo "----------------------------------------"

# Store the project root directory
PROJECT_ROOT=$(pwd)

# Source the Proxmox environment variables
source ./services/terraform/set-proxmox-env.sh

# Change into the terraform directory
cd "${PROJECT_ROOT}/services/terraform"

# --- Conditionally run Terraform ---
if [ "$RUN_TERRAFORM_APPLY" = true ]; then
  echo "Destroying existing Terraform-managed infrastructure (VM)..."
  terraform destroy -var="vm_names=[\"${TARGET_HOSTNAME}\"]" -auto-approve

  SLEEP_DURATION=1
  echo "Waiting ${SLEEP_DURATION} seconds for network/mDNS caches to clear before recreating VM..."
  sleep ${SLEEP_DURATION}

  echo "Initializing Terraform…"
  terraform init

  echo "Applying Terraform configuration (recreating infrastructure)..."
  terraform apply -var="vm_names=[\"${TARGET_HOSTNAME}\"]" -auto-approve
else
  # Ensure terraform is initialized even if we're not applying changes
  terraform init -input=false
fi

# Extract IP address from terraform output
IP=$(terraform output -json vm_ip_addresses \
     | jq -r --arg NAME "$TARGET_HOSTNAME" '.[$NAME] | .[][] | select(. != "127.0.0.1")' | head -n 1)

# Validate IP Address
if [ -z "$IP" ] || [ "$IP" == "null" ]; then
    echo "Error: Could not retrieve IP address for ${TARGET_HOSTNAME} from Terraform output." >&2
    if [ "$RUN_TERRAFORM_APPLY" = false ]; then
        echo "Maybe the VM doesn't exist or Terraform state is missing/corrupt?" >&2
        echo "Try running with the '--nuke' flag to create it." >&2
    else
        echo "Terraform apply might have failed to output the IP address." >&2
    fi
    exit 1
fi

echo "VM IP address (${TARGET_HOSTNAME}): $IP"

# Return to the project root
cd "${PROJECT_ROOT}"

# Update the hosts file with the new IP
mkdir -p services/ansible/inventory
echo "[iot_servers]" > services/ansible/inventory/hosts
echo "pxiots ansible_host=$IP" >> services/ansible/inventory/hosts
echo "" >> services/ansible/inventory/hosts
echo "[all:vars]" >> services/ansible/inventory/hosts
echo "ansible_python_interpreter=/usr/bin/python3" >> services/ansible/inventory/hosts

# Wait for SSH to become available on the VM
echo "Waiting for SSH to become available on ${TARGET_HOSTNAME} ($IP)..."
while ! ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 eric@"$IP" echo ready 2>/dev/null; do
  echo "Still waiting for SSH..."
  sleep 5
done

# Run the appropriate Ansible playbook
cd "${PROJECT_ROOT}/services/ansible"

if [ -n "$SPECIFIC_SERVICE" ]; then
  echo "Running Ansible playbook for ${SPECIFIC_SERVICE} service..."
  ansible-playbook "playbooks/${SPECIFIC_SERVICE}.yml"
else
  echo "Running main Ansible playbook for all services..."
  ansible-playbook playbooks/main.yml
fi

echo "Deployment complete! Your IoT services are now running on http://$IP"
echo "Current date: $(date)"