resource "azurerm_resource_group" "storage" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}