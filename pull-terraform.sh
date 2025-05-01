#!/usr/bin/env bash
# pull_terraform.sh - Script to pull the latest Terraform module and update the Proxmox module
cd ~/eprojects/iots6/services/terraform/proxmox-module
git pull origin main
cd ..
git add proxmox-module
git commit -m "Update Proxmox module with fixed outputs"
cd ~/eprojects/iots6
