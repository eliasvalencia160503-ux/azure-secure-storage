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

  network_rules {
    default_action = "Deny"
    ip_rules       = [var.my_public_ip]
    bypass         = ["AzureServices"]
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

resource "azurerm_storage_management_policy" "cleanup" {
  storage_account_id = azurerm_storage_account.storage.id

  rule {
    name    = "autocleanup"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than       = 365
      }
      version {
        delete_after_days_since_creation = 90
      }
    }
  }
}

resource "azurerm_storage_container_immutability_policy" "retention" {
  storage_container_resource_manager_id = azurerm_storage_container.storage_cont.id
  immutability_period_in_days           = 1
  locked                                = false
}

resource "azurerm_storage_share" "fileshare" {
  name               = "sharefile"
  storage_account_id = azurerm_storage_account.storage.id
  quota              = 1
}
