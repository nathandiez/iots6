variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "vm_size" {
  description = "Size of the virtual machine"
  type        = string
  default     = "Standard_B2s"  # 2 vCPUs, 4 GB RAM - good for IoT services
}

variable "tags" {
  description = "Tags to apply to the resources"
  type        = map(string)
  default     = {
    "Environment" = "Development"
    "Project"     = "IoT"
    "ManagedBy"   = "Terraform"
  }
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 30
}

variable "ssh_username" {
  description = "Username for SSH access"
  type        = string
  default     = "nathan"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/id_rsa.pub"  # Use RSA keys with Azure
}
