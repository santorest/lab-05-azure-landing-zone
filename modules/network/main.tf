# Hub-spoke network. Every subnet that can take an NSG gets one ending in deny-all inbound.
locals {
  nsg_exempt = ["GatewaySubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet"]
  subnets = merge([
    for vk, v in var.vnets : {
      for sk, s in v.subnets : "${vk}/${sk}" => { vnet = vk, name = sk, address_prefixes = s.address_prefixes }
    }
  ]...)
  nsg_subnets = { for k, s in local.subnets : k => s if !contains(local.nsg_exempt, s.name) }
  spokes      = { for k, v in var.vnets : k => v if k != "hub" }
  extra_rules = merge([
    for key, rules in var.nsg_rules : { for r in rules : "${key}/${r.name}" => merge(r, { nsg_key = key }) }
  ]...)
}

resource "azurerm_virtual_network" "this" {
  for_each            = var.vnets
  name                = "vnet-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = each.value.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnets
  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[each.value.vnet].name
  address_prefixes     = each.value.address_prefixes
}

resource "azurerm_network_security_group" "this" {
  for_each            = local.nsg_subnets
  name                = "nsg-${var.prefix}-${replace(each.key, "/", "-")}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "deny_all_inbound" {
  for_each                    = local.nsg_subnets
  name                        = "deny-all-inbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this[each.key].name
}

resource "azurerm_network_security_rule" "extra" {
  for_each                    = local.extra_rules
  name                        = each.value.name
  priority                    = each.value.priority
  direction                   = each.value.direction
  access                      = each.value.access
  protocol                    = each.value.protocol
  source_port_range           = "*"
  destination_port_ranges     = each.value.destination_port_ranges
  source_address_prefix       = each.value.source_address_prefix
  destination_address_prefix  = each.value.destination_address_prefix
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.this[each.value.nsg_key].name
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.nsg_subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  for_each                     = local.spokes
  name                         = "peer-hub-to-${each.key}"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this["hub"].name
  remote_virtual_network_id    = azurerm_virtual_network.this[each.key].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  for_each                     = local.spokes
  name                         = "peer-${each.key}-to-hub"
  resource_group_name          = var.resource_group_name
  virtual_network_name         = azurerm_virtual_network.this[each.key].name
  remote_virtual_network_id    = azurerm_virtual_network.this["hub"].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
