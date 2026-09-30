mock_provider "azurerm" {
  mock_resource "azurerm_policy_definition" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyDefinitions/deny-public-ip"
    }
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults = {
      id = "/providers/Microsoft.Management/managementGroups/corp/providers/Microsoft.Authorization/policyAssignments/mock"
    }
  }
}

# Distinct, well-formed IDs per management group, so the parent assertions can't pass by accident.
override_resource {
  target = azurerm_management_group.root
  values = { id = "/providers/Microsoft.Management/managementGroups/corp" }
}
override_resource {
  target = azurerm_management_group.level1["platform"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-platform" }
}
override_resource {
  target = azurerm_management_group.level1["landing-zones"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-landing-zones" }
}
override_resource {
  target = azurerm_management_group.level1["sandbox"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-sandbox" }
}
override_resource {
  target = azurerm_management_group.level2["connectivity"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-connectivity" }
}
override_resource {
  target = azurerm_management_group.level2["management"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-management" }
}
override_resource {
  target = azurerm_management_group.level2["identity"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-identity" }
}
override_resource {
  target = azurerm_management_group.level2["online"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-online" }
}
override_resource {
  target = azurerm_management_group.level2["internal"]
  values = { id = "/providers/Microsoft.Management/managementGroups/corp-internal" }
}

variables {
  prefix                     = "corp"
  location                   = "eastus2"
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  subscription_placement     = "online"
  allowed_locations          = ["eastus2", "centralus"]
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-corp-management/providers/Microsoft.OperationalInsights/workspaces/log-corp"
  budget_start_date          = "2026-10-01T00:00:00Z"
  budget_contact_emails      = ["secops@example.com"]
}

run "management_group_tree" {
  command = apply

  assert {
    condition     = length(output.management_group_ids) == 9
    error_message = "Expected corp + 3 level-1 + 5 level-2 management groups."
  }
  assert {
    condition = alltrue([
      for k in ["platform", "landing-zones", "sandbox"] :
      azurerm_management_group.level1[k].parent_management_group_id == azurerm_management_group.root.id
    ])
    error_message = "Level-1 groups must sit under corp."
  }
  assert {
    condition = alltrue([
      for k, parent in { connectivity = "platform", management = "platform", identity = "platform", online = "landing-zones", internal = "landing-zones" } :
      azurerm_management_group.level2[k].parent_management_group_id == azurerm_management_group.level1[parent].id
    ])
    error_message = "Level-2 groups have the wrong parents."
  }
  assert {
    condition     = azurerm_management_group_subscription_association.this[0].management_group_id == azurerm_management_group.level2["online"].id
    error_message = "Subscription must be placed under the chosen group."
  }
}

run "policies_assigned_at_root" {
  command = apply

  assert {
    condition     = azurerm_management_group_policy_assignment.allowed_locations.management_group_id == azurerm_management_group.root.id
    error_message = "Allowed-locations must be assigned at corp."
  }
  assert {
    condition     = jsondecode(azurerm_management_group_policy_assignment.allowed_locations.parameters).listOfAllowedLocations.value == ["eastus2", "centralus"]
    error_message = "Allowed-locations parameter must equal var.allowed_locations."
  }
  assert {
    condition     = toset(keys(azurerm_management_group_policy_assignment.require_tag)) == toset(["owner", "env", "cost-center"])
    error_message = "One require-tag assignment per required tag."
  }
  assert {
    condition     = jsondecode(azurerm_policy_definition.deny_public_ip.policy_rule).if.equals == "Microsoft.Network/publicIPAddresses"
    error_message = "Custom policy must target public IP addresses."
  }
  assert {
    condition     = jsondecode(azurerm_policy_definition.deny_public_ip.parameters).effect.defaultValue == "Deny"
    error_message = "Deny public IP must default to Deny."
  }
  assert {
    condition     = azurerm_management_group_policy_assignment.deny_public_ip.management_group_id == azurerm_management_group.root.id
    error_message = "Deny public IP must be assigned at corp."
  }
  assert {
    condition     = output.diagnostics_workspace_id == var.log_analytics_workspace_id
    error_message = "Key Vault diagnostics policy must point at the workspace."
  }
  assert {
    condition     = azurerm_management_group_policy_assignment.kv_diagnostics.identity[0].type == "SystemAssigned"
    error_message = "DeployIfNotExists needs a managed identity."
  }
  assert {
    condition     = toset(keys(azurerm_role_assignment.kv_diagnostics)) == toset(["Log Analytics Contributor", "Monitoring Contributor"])
    error_message = "The DINE identity needs Log Analytics Contributor and Monitoring Contributor."
  }
}

run "budget_thresholds" {
  command = apply

  assert {
    condition     = toset([for n in azurerm_consumption_budget_subscription.this.notification : n.threshold]) == toset([50, 80, 100])
    error_message = "Budget must alert at 50/80/100 %."
  }
  assert {
    condition     = alltrue([for n in azurerm_consumption_budget_subscription.this.notification : toset(n.contact_emails) == toset(["secops@example.com"])])
    error_message = "Every threshold notifies the contacts."
  }
}

run "no_placement_means_no_association" {
  command = apply
  variables {
    subscription_placement = null
  }

  assert {
    condition     = length(azurerm_management_group_subscription_association.this) == 0
    error_message = "No association without a placement."
  }
}

run "empty_allowed_locations_rejected" {
  command = plan
  variables {
    allowed_locations = []
  }
  expect_failures = [var.allowed_locations]
}

run "unknown_placement_rejected" {
  command = plan
  variables {
    subscription_placement = "prod"
  }
  expect_failures = [var.subscription_placement]
}

run "budget_start_must_be_first_of_month" {
  command = plan
  variables {
    budget_start_date = "2026-10-15T00:00:00Z"
  }
  expect_failures = [var.budget_start_date]
}

run "subscription_id_must_be_guid" {
  command = plan
  variables {
    subscription_id = "my-subscription"
  }
  expect_failures = [var.subscription_id]
}

run "budget_needs_contacts" {
  command = plan
  variables {
    budget_contact_emails = []
  }
  expect_failures = [var.budget_contact_emails]
}
