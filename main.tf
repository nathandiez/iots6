terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.76"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.5.6:8006"
  insecure = true
}

module "ned_iots6_server" {
  source = "./vm-module"
  
  vm_name     = "nediots6"
  mac_address = "52:54:00:12:33:02"
  tags        = ["terraform-managed", "iot-system"]
  cores       = 4
  memory      = 4096
  disk_size   = 40
  dns_servers = ["192.168.5.1", "8.8.8.8"]
}

output "server_ip" {
  value = module.ned_iots6_server.primary_ip
}
