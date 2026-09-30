mock_provider "azurerm" {
  mock_resource "azurerm_public_ip" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/publicIPAddresses/pip-mock"
    }
  }
  mock_resource "azurerm_firewall_policy" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/firewallPolicies/afwp-corp"
    }
  }
  mock_resource "azurerm_firewall" {
    defaults = {
      ip_configuration = { private_ip_address = "10.0.2.4" }
    }
  }
  mock_resource "azurerm_route_table" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/routeTables/rt-corp-spokes"
    }
  }
}

variables {
  prefix              = "corp"
  location            = "eastus2"
  resource_group_name = "rg-corp-connectivity"
  tags                = { owner = "platform-team", env = "prod", "cost-center" = "cc-001" }
}

run "off_by_default_creates_nothing" {
  command = apply

  assert {
    condition     = length(azurerm_firewall.this) == 0 && length(azurerm_public_ip.data) == 0 && length(azurerm_route_table.spokes) == 0
    error_message = "With enable_firewall=false the module must create nothing."
  }
  assert {
    condition     = output.private_ip == null && output.enabled == false
    error_message = "Outputs must report the firewall as absent."
  }
}

run "enabled_routes_spokes_through_firewall" {
  command = apply
  variables {
    enable_firewall               = true
    firewall_subnet_id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub/subnets/AzureFirewallSubnet"
    firewall_management_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/hub/subnets/AzureFirewallManagementSubnet"
    route_subnet_ids              = { "online/snet-app" = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/online/subnets/snet-app" }
  }

  assert {
    condition     = azurerm_firewall.this[0].sku_tier == "Basic"
    error_message = "Default tier is Basic (cheapest)."
  }
  assert {
    condition     = azurerm_route.default[0].address_prefix == "0.0.0.0/0" && azurerm_route.default[0].next_hop_type == "VirtualAppliance" && azurerm_route.default[0].next_hop_in_ip_address == "10.0.2.4"
    error_message = "Default route must go to the firewall's private IP."
  }
  assert {
    condition     = toset(keys(azurerm_subnet_route_table_association.spokes)) == toset(["online/snet-app"])
    error_message = "Each listed spoke subnet gets the route table."
  }
  assert {
    condition     = output.private_ip == "10.0.2.4" && output.enabled
    error_message = "Outputs must report the firewall."
  }
}

run "enabled_without_subnets_rejected" {
  command = plan
  variables {
    enable_firewall = true
  }
  expect_failures = [var.firewall_subnet_id, var.firewall_management_subnet_id]
}
