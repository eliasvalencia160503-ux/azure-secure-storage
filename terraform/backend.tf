terraform {
  backend "azurerm" {
    storage_account_name = "sttfstatec4dbcb2r"
    container_name       = "tfstate"
    key                  = "securestg.tfstate"
    use_azuread_auth     = true
  }
}
