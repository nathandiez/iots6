# IoT Infrastructure with Proxmox & Terraform

Complete IoT infrastructure deployment using Terraform, Ansible, and Proxmox. Automatically provisions VMs with TimescaleDB, Mosquitto MQTT broker, and custom IoT data processing service.

## Architecture

```
IoT Devices → MQTT Broker → IoT Service → TimescaleDB
```

## Project Structure

```
iots6/
├── main.tf                 # Main Terraform configuration
├── vm-module/             # Reusable Proxmox VM module
├── deploy.sh              # Main deployment script
├── set-proxmox-env.sh     # Environment configuration
├── ansible/               # Service deployment automation
└── services/iot_service/  # Custom IoT data processor
```

## Quick Start

### Prerequisites

- Proxmox VE server with Ubuntu 22.04 template (VMID 9002)
- Terraform and Ansible installed
- SSH key pair (`~/.ssh/id_ed25519.pub`)
- Copy `set-proxmox-env.sh.template` to `set-proxmox-env.sh` with your API token
- Copy `terraform.tfvars.example` to `terraform.tfvars` with your settings

### Deploy

```bash
# Configure Proxmox credentials (copy set-proxmox-env.sh.template first)
source ./set-proxmox-env.sh

# Deploy everything
./deploy.sh --nuke
```

### Test

```bash
# Send test MQTT message
mosquitto_pub -h <VM_IP> -t iots4/test -m '{
  "device_id": "test-sensor",
  "event_type": "sensor_data", 
  "temperature": 25.5,
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Check database
ssh nathan@<VM_IP>
docker exec timescaledb psql -U iotuser -d iotdb -c "SELECT * FROM sensor_data;"
```

### Destroy

```bash
terraform destroy
```

## Configuration

**VM Specs**: 4 cores, 4GB RAM, 40GB disk
**Ports**: MQTT (1883), PostgreSQL (5432)
**Topics**: `iots4/#`

### Required Files

Before deploying, create these files from the provided templates:

1. **set-proxmox-env.sh** (from set-proxmox-env.sh.template)
   ```bash
   export PROXMOX_VE_API_TOKEN='root@pam!YOUR_TOKEN_NAME=YOUR_TOKEN_HERE'
   ```

2. **terraform.tfvars** (from terraform.tfvars.example)
   ```hcl
   proxmox_endpoint = "https://YOUR_PROXMOX_IP:8006"
   vm_name         = "your-vm-name"
   mac_address     = "52:54:00:12:34:56"
   dns_servers     = ["YOUR_DNS_SERVER", "8.8.8.8"]
   ```

## Database Schema

```sql
CREATE TABLE sensor_data (
    time TIMESTAMPTZ NOT NULL,
    device_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    temperature FLOAT,
    humidity FLOAT,
    pressure FLOAT,
    temp_sensor_type TEXT,
    motion TEXT,
    switch TEXT,
    version TEXT,
    uptime TEXT
);
```

## Proxmox Setup

### Host Installation

1. Install Proxmox VE on target machine
2. Configure static network:
   - IP: <YOUR_PROXMOX_IP>/22
   - Gateway: <YOUR_GATEWAY>
   - DNS: <YOUR_DNS_SERVER>, 8.8.8.8

### Network Configuration

```
auto vmbr0
iface vmbr0 inet static
    address <YOUR_PROXMOX_IP>/22
    gateway <YOUR_GATEWAY>
    bridge_ports enp3s0
    bridge_stp off
    bridge_fd 0
    dns-nameservers <YOUR_DNS_SERVER> 8.8.8.8
```

### Ubuntu Template Creation

```bash
# Download Ubuntu cloud image
wget -P /var/lib/vz/template/iso/ https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Install required packages
virt-customize -a /var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img --install qemu-guest-agent,avahi-daemon
virt-customize -a /var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img --run-command 'systemctl enable qemu-guest-agent.service'

# Create and configure VM
qm create 9002 --name "ubuntu-2204-jammy-template" --memory 4096 --cores 4 --net0 virtio,bridge=vmbr0
qm importdisk 9002 /var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img local-lvm
qm set 9002 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9002-disk-0
qm resize 9002 scsi0 +18G
qm set 9002 --boot c --bootdisk scsi0
qm set 9002 --ide2 local-lvm:cloudinit
qm set 9002 --serial0 socket --vga serial0
qm set 9002 --agent enabled=1
qm template 9002
```

## Development

**Redeploy**: `./deploy.sh --nuke`
**Logs**: `docker logs iot_service -f`
**Monitor**: `docker ps && docker stats`