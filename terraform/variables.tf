variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into (set in terraform.tfvars, never committed)"
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "eastus"
}

variable "prefix" {
  type        = string
  description = "prefix for every resource"
  default     = "securestg"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource for cost tracking and ownership"
  default = {
    project     = "azure-secure-storage"
    environment = "lab"
    owner       = "elias"
    managed_by  = "terraform"
  }
}

variable "my_public_ip" {
  type        = string
  description = "My public IP, temporarily allowed through the storage firewall for testing"
}