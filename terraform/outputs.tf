output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.storage.name
}

output "location" {
  description = "Azure region of the resource group"
  value       = azurerm_resource_group.storage.location
}