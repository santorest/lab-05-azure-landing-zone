# Cross-module wiring. Mock providers: nothing is sent to Azure. IDs are well-formed because mock
# providers still run the real providers' argument validation.
mock_provider "azurerm" {
  mock_resource "azurerm_resource_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-mock" }
  }
  mock_resource "azurerm_management_group" {
    defaults = { id = "/providers/Microsoft.Management/managementGroups/corp" }
  }
  mock_resource "azurerm_policy_definition" {
    defaults = { id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyDefinitions/deny-public-ip" }
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = { id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyAssignments/deny-public-ip" }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-mock" }
  }
  mock_resource "azurerm_subnet" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-mock/subnets/snet-mock" }
  }
  mock_resource "azurerm_network_security_group" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/networkSecurityGroups/nsg-mock" }
  }
  mock_resource "azurerm_storage_account" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-workload/providers/Microsoft.Storage/storageAccounts/corpworkload01" }
  }
  mock_resource "azurerm_private_dns_zone" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net" }
  }
  mock_resource "azurerm_log_analytics_workspace" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.OperationalInsights/workspaces/log-corp" }
  }
  mock_resource "azurerm_key_vault" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.KeyVault/vaults/kv-corp-platform" }
  }
  mock_resource "azurerm_public_ip" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/publicIPAddresses/pip-mock" }
  }
  mock_resource "azurerm_firewall_policy" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/firewallPolicies/afwp-corp" }
  }
  mock_resource "azurerm_firewall" {
    defaults = { ip_configuration = { private_ip_address = "10.0.2.4" } }
  }
  mock_resource "azurerm_route_table" {
    defaults = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/routeTables/rt-corp-spokes" }
  }
}

mock_provider "azuread" {
  mock_resource "azuread_group" {
    defaults = { object_id = "33333333-3333-3333-3333-333333333333" }
  }
}

# A distinct ID for the connectivity resource group, so the exemption-scope assertion can't pass by accident.
override_resource {
  target = azurerm_resource_group.this["connectivity"]
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity" }
}

# Distinct IDs for the two private DNS zones and the deny-public-IP assignment, so the wiring assertions can't
# pass because every mocked zone or assignment shares one ID.
override_resource {
  target = module.network.azurerm_private_dns_zone.vault
  values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net" }
}
override_resource {
  target = module.governance.azurerm_management_group_policy_assignment.deny_public_ip
  values = { id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyAssignments/deny-public-ip-distinct" }
}

variables {
  subscription_id       = "00000000-0000-0000-0000-000000000000"
  tenant_id             = "00000000-0000-0000-0000-000000000000"
  tags                  = { owner = "platform-team", env = "prod", "cost-center" = "cc-001" }
  storage_account_name  = "corpworkload01"
  key_vault_name        = "kv-corp-platform"
  budget_start_date     = "2026-10-01T00:00:00Z"
  budget_contact_emails = ["secops@example.com"]
}

run "default_landing_zone" {
  command = apply

  assert {
    condition     = toset(keys(output.nsg_ids)) == toset(["hub/snet-shared", "online/snet-app", "internal/snet-app", "internal/snet-private-endpoints"])
    error_message = "Default address plan: four NSG-protected subnets."
  }
  assert {
    condition     = alltrue([for k in keys(output.nsg_ids) : contains(output.diagnostic_target_keys, "nsg-${replace(k, "/", "-")}")]) && contains(output.diagnostic_target_keys, "storage-blob")
    error_message = "Every NSG and the workload blob service send diagnostics to the workspace."
  }
  assert {
    condition     = module.governance.diagnostics_workspace_id == output.workspace_id
    error_message = "Key Vault DINE policy must use the landing-zone workspace."
  }
  assert {
    condition     = output.firewall_enabled == false && output.firewall_exemption_count == 0
    error_message = "No firewall and no public-IP exemption by default."
  }
  assert {
    condition     = alltrue([for rg in azurerm_resource_group.this : rg.tags == var.tags])
    error_message = "Resource groups carry the required tags."
  }
  assert {
    condition     = module.logging.key_vault_private_dns_zone_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    error_message = "The Key Vault private endpoint must use the vaultcore zone, not the blob zone."
  }
}

run "firewall_enabled_adds_subnets_and_exemption" {
  command = apply
  variables {
    enable_firewall = true
  }

  # azurerm checks that the firewall's subnets carry their reserved names.
  override_resource {
    target = module.network.azurerm_subnet.this["hub/AzureFirewallSubnet"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-corp-hub/subnets/AzureFirewallSubnet" }
  }
  override_resource {
    target = module.network.azurerm_subnet.this["hub/AzureFirewallManagementSubnet"]
    values = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-corp-hub/subnets/AzureFirewallManagementSubnet" }
  }

  assert {
    condition     = output.firewall_enabled && output.firewall_exemption_count == 1 && output.firewall_private_ip == "10.0.2.4"
    error_message = "Firewall on: exactly one public-IP exemption (connectivity RG)."
  }
  assert {
    condition     = azurerm_resource_group_policy_exemption.firewall_public_ip[0].resource_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-connectivity"
    error_message = "Exemption must be scoped to the connectivity resource group only."
  }
  assert {
    condition     = azurerm_resource_group_policy_exemption.firewall_public_ip[0].policy_assignment_id == "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyAssignments/deny-public-ip-distinct"
    error_message = "The exemption must waive the deny-public-IP assignment, not another one."
  }
  assert {
    condition     = contains(keys(module.network.subnet_ids), "hub/AzureFirewallSubnet") && contains(keys(module.network.subnet_ids), "hub/AzureFirewallManagementSubnet")
    error_message = "Firewall subnets are added to the hub."
  }
}

# --- Review Focus 5 -------------------------------------------------------------------------

run "missing_required_tag_rejected" {
  command = plan
  variables {
    tags = { owner = "platform-team", env = "prod" }
  }
  expect_failures = [var.tags]
}

run "empty_required_tag_rejected" {
  command = plan
  variables {
    tags = { owner = "", env = "prod", "cost-center" = "cc-001" }
  }
  expect_failures = [var.tags]
}

run "location_outside_allowed_locations_rejected" {
  command = plan
  variables {
    location          = "westeurope"
    allowed_locations = ["eastus2"]
  }
  expect_failures = [var.location]
}
