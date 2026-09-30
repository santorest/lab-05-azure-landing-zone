output "management_group_ids" {
  description = "Management group IDs by key."
  value       = module.governance.management_group_ids
}

output "workspace_id" {
  description = "Log Analytics / Sentinel workspace."
  value       = module.logging.workspace_id
}

output "nsg_ids" {
  description = "NSG IDs keyed by the subnet they protect."
  value       = module.network.nsg_ids
}

output "diagnostic_target_keys" {
  description = "External resources sending diagnostics to the workspace."
  value       = module.logging.diagnostic_target_keys
}

output "firewall_enabled" {
  description = "Whether Azure Firewall is deployed."
  value       = module.firewall.enabled
}

output "firewall_private_ip" {
  description = "Firewall private IP, or null."
  value       = module.firewall.private_ip
}

output "firewall_exemption_count" {
  description = "Number of deny-public-IP exemptions (0 without the firewall)."
  value       = length(azurerm_resource_group_policy_exemption.firewall_public_ip)
}
