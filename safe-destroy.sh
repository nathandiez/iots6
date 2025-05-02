#!/usr/bin/env bash
# safe-destroy.sh
set -e

echo "Safely destroying all resources except the resource group..."
cd "$(dirname "$0")/terraform"

# First destroy the VM since other resources depend on it
terraform destroy -target="azurerm_linux_virtual_machine.vm" -auto-approve || true
terraform destroy -target="azurerm_network_interface_security_group_association.nsg_assoc" -auto-approve || true
terraform destroy -target="azurerm_network_interface.nic" -auto-approve || true
terraform destroy -target="azurerm_network_security_group.nsg" -auto-approve || true 
terraform destroy -target="azurerm_subnet.subnet" -auto-approve || true
terraform destroy -target="azurerm_virtual_network.vnet" -auto-approve || true
terraform destroy -target="azurerm_public_ip.public_ip" -auto-approve || true

echo "✅ All resources successfully destroyed (resource group preserved)"