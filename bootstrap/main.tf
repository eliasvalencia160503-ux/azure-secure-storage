data "azurerm_client_config" "current" {
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  lower   = true
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "tfstate" {
  name     = "securestg-tfstate-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "tfstate" {
  #checkov:skip=CKV_AZURE_59:State store must be reachable by GitHub runners (dynamic public IPs) and my laptop; protected by identity instead: shared keys off, no anonymous access, Entra ID + RBAC data role required 
  #checkov:skip=CKV_AZURE_206:Lab only using disposable test data, destroyed each session; LRS is enough and has less cost.
  #checkov:skip=CKV_AZURE_33:Lab does not use queues, therefore it is not needed.
  #checkov:skip=CKV2_AZURE_1:Lab already had double encryption with Microsoft-Managed keys and infrastructure_encryption_enabled, I would need Azure Key Vault for CMK.
  #checkov:skip=CKV_AZURE_35:Same as CKV_AZURE_59: no IP allow-list possible for GitHub runners; access requires Entra ID + RBAC, keys and anonymous access disabled.
  #checkov:skip=CKV_AZURE_206:Holds only a few-KB lab state file; tracked resources are in the same region, so a geo copy adds little. Bad applies and deletes covered by versioning, 7-day soft delete and prevent_destroy.
  name                              = "sttfstate${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.tfstate.name
  location                          = azurerm_resource_group.tfstate.location
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

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "blob_contributor_me" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "tfstate" {
  #checkov:skip=CKV2_AZURE_21:Monitoring and diagnostic logs were not included in this lab
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"


  depends_on = [azurerm_role_assignment.blob_contributor_me]
}

resource "azuread_application_registration" "github" {
  display_name = "github-azure-secure-storage-ci"
}

resource "azuread_service_principal" "github" {
  client_id = azuread_application_registration.github.client_id
}

resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application_registration.github.id
  display_name   = "github-pull-requests"
  issuer         = "https://token.actions.githubusercontent.com"
  audiences      = ["api://AzureADTokenExchange"]
  subject        = "repo:eliasvalencia160503-ux/azure-secure-storage:pull_request"
}

resource "azurerm_role_assignment" "github_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.github.object_id
}

resource "azurerm_role_assignment" "github_state" {
  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.github.object_id
}

