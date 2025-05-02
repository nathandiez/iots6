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
