# Optional Azure Firewall Basic: the costly alternative to the NSG-only design (docs/design-decisions.md).
locals {
  n = var.enable_firewall ? 1 : 0
}

resource "azurerm_public_ip" "data" {
  count               = local.n
  name                = "pip-${var.prefix}-fw"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_public_ip" "management" {
  count               = local.n
  name                = "pip-${var.prefix}-fw-mgmt"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  #checkov:skip=CKV_AZURE_220:IDPS exists only on the Premium SKU; this optional firewall is Basic by design (cost).
  count               = local.n
  name                = "afwp-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Basic"
  tags                = var.tags
}

resource "azurerm_firewall" "this" {
  #checkov:skip=CKV_AZURE_216:Threat intelligence on the Basic SKU supports Alert mode only; Deny needs Standard or Premium.
  count               = local.n
  name                = "afw-${var.prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Basic"
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  tags                = var.tags

  ip_configuration {
    name                 = "data"
    subnet_id            = var.firewall_subnet_id
    public_ip_address_id = azurerm_public_ip.data[0].id
  }

  management_ip_configuration {
    name                 = "management"
    subnet_id            = var.firewall_management_subnet_id
    public_ip_address_id = azurerm_public_ip.management[0].id
  }
}

resource "azurerm_route_table" "spokes" {
  count                         = local.n
  name                          = "rt-${var.prefix}-spokes"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags
}

resource "azurerm_route" "default" {
  count                  = local.n
  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.spokes[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.this[0].ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "spokes" {
  for_each       = var.enable_firewall ? var.route_subnet_ids : {}
  subnet_id      = each.value
  route_table_id = azurerm_route_table.spokes[0].id
}
