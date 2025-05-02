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
