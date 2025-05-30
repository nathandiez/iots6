terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

provider "proxmox" {
  endpoint = "https://YOUR_PROXMOX_IP:8006"
  insecure = true
}

module "ned_iots6_server" {
  source = "./vm-module"
  
  vm_name     = "your-vm-name"
  mac_address = "52:54:00:12:34:56"
  tags        = ["terraform-managed", "iot-system"]
  cores       = 4
  memory      = 4096
  disk_size   = 40
  dns_servers = ["YOUR_DNS_SERVER", "8.8.8.8"]
}

output "server_ip" {
  value = module.ned_iots6_server.primary_ip
}
