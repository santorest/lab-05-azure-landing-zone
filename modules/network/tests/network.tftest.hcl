mock_provider "azurerm" {
  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-mock"
    }
  }
  mock_resource "azurerm_subnet" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/snet-mock"
    }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/networkSecurityGroups/nsg-mock"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-workload/providers/Microsoft.Storage/storageAccounts/corpworkload01"
    }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    }
  }
}

# A distinct ID for the private-endpoint subnet, so the placement assertion can't pass by accident.
override_resource {
  target = azurerm_subnet.this["internal/snet-private-endpoints"]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-corp-internal/subnets/snet-private-endpoints"
  }
}

variables {
  prefix                       = "corp"
  location                     = "eastus2"
  resource_group_name          = "rg-corp-connectivity"
  workload_resource_group_name = "rg-corp-workload"
  storage_account_name         = "corpworkload01"
  tags                         = { owner = "platform-team", env = "prod", "cost-center" = "cc-001" }
  vnets = {
    hub = {
      address_space = ["10.0.0.0/22"]
      subnets = {
        "snet-shared"   = { address_prefixes = ["10.0.0.0/24"] }
        "GatewaySubnet" = { address_prefixes = ["10.0.1.0/27"] }
      }
    }
    online = {
      address_space = ["10.1.0.0/22"]
      subnets       = { "snet-app" = { address_prefixes = ["10.1.0.0/24"] } }
    }
    internal = {
      address_space = ["10.2.0.0/22"]
      subnets = {
        "snet-app"               = { address_prefixes = ["10.2.0.0/24"] }
        "snet-private-endpoints" = { address_prefixes = ["10.2.1.0/24"] }
      }
    }
  }
  nsg_rules = {
    "online/snet-app" = [{
      name                  = "allow-https-in", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp",
      source_address_prefix = "Internet", destination_address_prefix = "*", destination_port_ranges = ["443"]
    }]
  }
}

run "every_non_gateway_subnet_has_a_default_deny_nsg" {
  command = apply

  assert {
    condition     = toset(keys(azurerm_subnet_network_security_group_association.this)) == toset(["hub/snet-shared", "online/snet-app", "internal/snet-app", "internal/snet-private-endpoints"])
    error_message = "Every subnet except GatewaySubnet/AzureFirewall* must have an NSG."
  }
  assert {
    condition     = alltrue([for r in azurerm_network_security_rule.deny_all_inbound : r.priority == 4096 && r.access == "Deny" && r.direction == "Inbound" && r.source_address_prefix == "*"])
    error_message = "Each NSG ends with deny-all inbound at 4096."
  }
  assert {
    condition     = toset(keys(azurerm_network_security_rule.deny_all_inbound)) == toset(keys(azurerm_network_security_group.this))
    error_message = "One deny-all rule per NSG."
  }
  assert {
    condition     = azurerm_network_security_rule.extra["online/snet-app/allow-https-in"].destination_port_ranges == toset(["443"])
    error_message = "HTTPS from the Internet is a legitimate rule and must be accepted."
  }
}

run "hub_spoke_peering" {
  command = apply

  assert {
    condition     = toset(keys(azurerm_virtual_network_peering.hub_to_spoke)) == toset(["online", "internal"]) && toset(keys(azurerm_virtual_network_peering.spoke_to_hub)) == toset(["online", "internal"])
    error_message = "Hub must peer both ways with each spoke."
  }
}

run "storage_is_private" {
  command = apply

  assert {
    condition     = azurerm_storage_account.workload.public_network_access_enabled == false && azurerm_storage_account.workload.shared_access_key_enabled == false
    error_message = "Workload storage: no public network access, no shared keys."
  }
  assert {
    condition     = azurerm_private_endpoint.blob.subnet_id == azurerm_subnet.this["internal/snet-private-endpoints"].id
    error_message = "Private endpoint must live in the private-endpoint subnet."
  }
  assert {
    condition     = tolist(azurerm_private_endpoint.blob.private_service_connection[0].subresource_names) == tolist(["blob"])
    error_message = "Private endpoint targets blob."
  }
  assert {
    condition     = azurerm_private_dns_zone.blob.name == "privatelink.blob.core.windows.net" && toset(keys(azurerm_private_dns_zone_virtual_network_link.blob)) == toset(["hub", "online", "internal"])
    error_message = "Blob private DNS zone must be linked to every VNet."
  }
}

# --- Review Focus 1: spellings of management exposure ---------------------------------------

run "rdp_from_internet_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "rdp", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "Internet", destination_address_prefix = "*", destination_port_ranges = ["3389"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "ssh_from_star_lowercase_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "ssh", priority = 100, direction = "inbound", access = "allow", protocol = "Tcp", source_address_prefix = "*", destination_address_prefix = "*", destination_port_ranges = ["22"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "range_covering_ssh_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "range", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "internet", destination_address_prefix = "*", destination_port_ranges = ["20-25"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "all_ports_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "all", priority = 100, direction = "Inbound", access = "Allow", protocol = "*", source_address_prefix = "0.0.0.0/0", destination_address_prefix = "*", destination_port_ranges = ["1-65535"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "winrm_hidden_in_list_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "list", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "::/0", destination_address_prefix = "*", destination_port_ranges = ["443", "5986"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "star_port_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "star", priority = 100, direction = "Inbound", access = "Allow", protocol = "*", source_address_prefix = "Internet", destination_address_prefix = "*", destination_port_ranges = ["*"] }] }
  }
  expect_failures = [var.nsg_rules]
}

# --- Review Focus 2: rule placement and priorities ------------------------------------------

run "unknown_subnet_key_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-db" = [{ name = "x", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "10.0.0.0/24", destination_address_prefix = "*", destination_port_ranges = ["1433"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "exempt_subnet_key_rejected" {
  command = plan
  variables {
    nsg_rules = { "hub/GatewaySubnet" = [{ name = "x", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "10.0.0.0/24", destination_address_prefix = "*", destination_port_ranges = ["443"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "duplicate_priority_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [
      { name = "a", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "10.0.0.0/24", destination_address_prefix = "*", destination_port_ranges = ["443"] },
      { name = "b", priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "10.0.0.0/24", destination_address_prefix = "*", destination_port_ranges = ["8443"] },
    ] }
  }
  expect_failures = [var.nsg_rules]
}

run "priority_out_of_range_rejected" {
  command = plan
  variables {
    nsg_rules = { "online/snet-app" = [{ name = "x", priority = 4096, direction = "Inbound", access = "Allow", protocol = "Tcp", source_address_prefix = "10.0.0.0/24", destination_address_prefix = "*", destination_port_ranges = ["443"] }] }
  }
  expect_failures = [var.nsg_rules]
}

run "hub_is_required" {
  command = plan
  variables {
    vnets = {
      internal = {
        address_space = ["10.2.0.0/22"]
        subnets       = { "snet-private-endpoints" = { address_prefixes = ["10.2.1.0/24"] } }
      }
    }
    nsg_rules = {}
  }
  expect_failures = [var.vnets]
}
