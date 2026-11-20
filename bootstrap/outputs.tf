output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.tfstate.name
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.tfstate.name
}

output "storage_container_name" {
  description = "Name of the storage container"
  value       = azurerm_storage_container.tfstate.name
}

output "client_id" {
  description = "Client ID of the GitHub Actions app registration, used for OIDC login"
  value       = azuread_application_registration.github.client_id
}

output "tenant_id" {
  description = "Entra ID tenant ID, used by GitHub Actions to log in"
  value       = data.azurerm_client_config.current.tenant_id
}