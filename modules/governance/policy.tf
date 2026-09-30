# Guardrails assigned at the root management group, so every subscription below inherits them.
# Built-in IDs verified against github.com/Azure/azure-policy (2026-09-29).
locals {
  builtin = {
    allowed_locations = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
    require_tag       = "/providers/Microsoft.Authorization/policyDefinitions/871b6d14-10aa-478d-b590-94f262ecfa99"
    kv_diagnostics    = "/providers/Microsoft.Authorization/policyDefinitions/951af2fa-529b-416e-ab6e-066fd85ac459"
  }
}

resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Allowed locations"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = local.builtin.allowed_locations
  parameters           = jsonencode({ listOfAllowedLocations = { value = var.allowed_locations } })
}

resource "azurerm_management_group_policy_assignment" "require_tag" {
  for_each             = toset(var.required_tags)
  name                 = "require-tag-${each.key}"
  display_name         = "Require tag '${each.key}' on resources"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = local.builtin.require_tag
  parameters           = jsonencode({ tagName = { value = each.key } })
}

# Custom: no public IPs anywhere. The optional firewall gets a resource-group exemption (landing-zone root).
resource "azurerm_policy_definition" "deny_public_ip" {
  name                = "deny-public-ip"
  policy_type         = "Custom"
  mode                = "All"
  display_name        = "Deny public IP addresses"
  management_group_id = azurerm_management_group.root.id
  policy_rule = jsonencode({
    "if"   = { field = "type", equals = "Microsoft.Network/publicIPAddresses" }
    "then" = { effect = "[parameters('effect')]" }
  })
  parameters = jsonencode({
    effect = { type = "String", allowedValues = ["Deny", "Audit", "Disabled"], defaultValue = "Deny" }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_public_ip" {
  name                 = "deny-public-ip"
  display_name         = "Deny public IP addresses"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = azurerm_policy_definition.deny_public_ip.id
}

resource "azurerm_management_group_policy_assignment" "kv_diagnostics" {
  name                 = "diag-keyvault"
  display_name         = "Key Vault diagnostics to Log Analytics"
  management_group_id  = azurerm_management_group.root.id
  policy_definition_id = local.builtin.kv_diagnostics
  location             = var.location
  parameters           = jsonencode({ logAnalytics = { value = var.log_analytics_workspace_id } })

  identity {
    type = "SystemAssigned"
  }
}

# The roles the built-in DeployIfNotExists definition declares (roleDefinitionIds).
resource "azurerm_role_assignment" "kv_diagnostics" {
  for_each             = toset(["Log Analytics Contributor", "Monitoring Contributor"])
  scope                = azurerm_management_group.root.id
  role_definition_name = each.key
  principal_id         = azurerm_management_group_policy_assignment.kv_diagnostics.identity[0].principal_id
}
