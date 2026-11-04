output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.storage.name
}

output "location" {
  description = "Azure region of the resource group"
  value       = azurerm_resource_group.storage.location
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.storage.name
}

output "storage_account_id" {
  description = "Full resource ID of the storage account (used as the RBAC scope)"
  value       = azurerm_storage_account.storage.id
}