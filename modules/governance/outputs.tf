output "management_group_ids" {
  description = "Management group IDs keyed corp, platform, landing-zones, sandbox, connectivity, management, identity, online, internal."
  value       = local.management_group_ids
}

output "deny_public_ip_assignment_id" {
  description = "Assignment ID for exemptions (the optional firewall's resource group)."
  value       = azurerm_management_group_policy_assignment.deny_public_ip.id
}

output "diagnostics_workspace_id" {
  description = "Workspace the Key Vault diagnostics policy deploys to."
  value       = jsondecode(azurerm_management_group_policy_assignment.kv_diagnostics.parameters).logAnalytics.value
}
