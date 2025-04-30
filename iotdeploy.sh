#!/usr/bin/env bash
set -e

IP=${1:-$(terraform -chdir=services/terraform output -json vm_ip_addresses | jq -r '.nediots | .[][] | select(. != "127.0.0.1")' | head -n 1)}

if [ -z "$IP" ] || [ "$IP" == "null" ]; then
  echo "Error: No valid IP address. Provide IP as argument."
  exit 1
fi

echo "Deploying IoT Service to $IP"

mkdir -p services/ansible/inventory
cat > services/ansible/inventory/hosts << EOF
[iot_servers]
nediots ansible_host=$IP

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

cd services/ansible
ansible-playbook playbooks/iot_service.yml

echo "IoT Service deployment completed!"