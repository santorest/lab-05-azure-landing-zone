# Landing zone root: composes governance, network, optional firewall, logging and identity.
locals {
  firewall_subnets = var.enable_firewall ? {
    "AzureFirewallSubnet"           = { address_prefixes = ["10.0.2.0/26"] }
    "AzureFirewallManagementSubnet" = { address_prefixes = ["10.0.2.64/26"] }
  } : {}

  # Address plan: docs/design-decisions.md.
  vnets = {
    hub = {
      address_space = ["10.0.0.0/22"]
      subnets = merge({
        "snet-shared"   = { address_prefixes = ["10.0.0.0/24"] }
        "GatewaySubnet" = { address_prefixes = ["10.0.1.0/27"] }
      }, local.firewall_subnets)
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
}

resource "azurerm_resource_group" "this" {
  for_each = toset(["connectivity", "management", "workload"])
  name     = "rg-${var.prefix}-${each.key}"
  location = var.location
  tags     = var.tags
}

module "network" {
  source                       = "../modules/network"
  prefix                       = var.prefix
  location                     = var.location
  resource_group_name          = azurerm_resource_group.this["connectivity"].name
  workload_resource_group_name = azurerm_resource_group.this["workload"].name
  storage_account_name         = var.storage_account_name
  vnets                        = local.vnets
  nsg_rules                    = var.nsg_rules
  tags                         = var.tags
}

module "firewall" {
  source                        = "../modules/firewall"
  enable_firewall               = var.enable_firewall
  prefix                        = var.prefix
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this["connectivity"].name
  firewall_subnet_id            = var.enable_firewall ? module.network.subnet_ids["hub/AzureFirewallSubnet"] : null
  firewall_management_subnet_id = var.enable_firewall ? module.network.subnet_ids["hub/AzureFirewallManagementSubnet"] : null
  route_subnet_ids              = { for k in ["online/snet-app", "internal/snet-app"] : k => module.network.subnet_ids[k] }
  tags                          = var.tags
}

module "logging" {
  source              = "../modules/logging"
  prefix              = var.prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.this["management"].name
  tenant_id           = var.tenant_id
  subscription_id     = var.subscription_id
  key_vault_name      = var.key_vault_name
  rules_file          = "${path.root}/../detections/rules.yaml"
  queries_dir         = "${path.root}/../detections"
  tags                = var.tags
  diagnostic_targets = merge(
    { for k, id in module.network.nsg_ids : "nsg-${replace(k, "/", "-")}" => { resource_id = id, category_groups = ["allLogs"] } },
    { "storage-blob" = { resource_id = "${module.network.storage_account_id}/blobServices/default", category_groups = ["allLogs"] } },
  )
}

module "governance" {
  source                     = "../modules/governance"
  prefix                     = var.prefix
  location                   = var.location
  subscription_id            = var.subscription_id
  subscription_placement     = var.subscription_placement
  allowed_locations          = var.allowed_locations
  log_analytics_workspace_id = module.logging.workspace_id
  budget_amount              = var.budget_amount
  budget_start_date          = var.budget_start_date
  budget_contact_emails      = var.budget_contact_emails
}

module "identity" {
  source               = "../modules/identity"
  prefix               = var.prefix
  subscription_id      = var.subscription_id
  ca_state             = var.ca_state
  break_glass_group_id = var.break_glass_group_id
}

# Single subscription: an exemption at the connectivity management group would never apply, so the
# firewall's public IPs are exempted at its resource group, and only when the firewall exists.
resource "azurerm_resource_group_policy_exemption" "firewall_public_ip" {
  count                = var.enable_firewall ? 1 : 0
  name                 = "firewall-public-ip"
  resource_group_id    = azurerm_resource_group.this["connectivity"].id
  policy_assignment_id = module.governance.deny_public_ip_assignment_id
  exemption_category   = "Waiver"
  description          = "Azure Firewall needs public IPs for its data and management interfaces; nothing else may have one."
}
