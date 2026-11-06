resource "azurerm_resource_group" "storage" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}

resource "azurerm_storage_account" "storage" {
  name                              = "${var.prefix}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.storage.name
  location                          = azurerm_resource_group.storage.location
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

data "azurerm_client_config" "current" {
}

resource "azurerm_role_assignment" "blob_contributor_me" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "storage_cont" {
  name                  = "privatecont"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"


  depends_on = [azurerm_role_assignment.blob_contributor_me]
}