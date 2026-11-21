variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into (set in terraform.tfvars, never committed)"
}

variable "location" {
  type        = string
  description = "Azure region for all resources"
  default     = "eastus"
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to every resource for cost tracking and ownership"
  default = {
    project     = "azure-secure-storage"
    environment = "lab"
    owner       = "elias"
    managed_by  = "terraform"
    purpose     = "tfstate"
  }
}