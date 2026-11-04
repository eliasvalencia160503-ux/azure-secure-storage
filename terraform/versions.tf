# Which Terraform CLI and which providers this configuration needs.
terraform {
  # 1.16 or newer, but never 2.0 (a major version can contain breaking changes).
  required_version = ">= 1.16, < 2.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # Pessimistic constraint: at least 5.12, any later 5.x, never 6.0.
      version = "~> 5.12"
    }
    random = {
      source = "hashicorp/random"
      # Pessimistic constraint: at least 3.5, any later 3.x, never 4.0
      version = "~> 3.5"
    }
  }
}
