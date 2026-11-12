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

output "object_id" {
  description = "Entra ID object ID of the identity running Terraform; receives the Storage Blob Data role"
  value       = data.azurerm_client_config.current.object_id
}

output "storage_container_name" {
  description = "Name of the storage container"
  value       = azurerm_storage_container.storage_cont.name
}

output "file_share_name" {
  description = "Name of the Azure Files Share"
  value       = azurerm_storage_share.fileshare.name
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.stvnet.name
}

output "private_endpoint_ip" {
  description = "Private IP of the blob private endpoint inside the pe subnet"
  value       = azurerm_private_endpoint.pe.private_service_connection[0].private_ip_address
}
