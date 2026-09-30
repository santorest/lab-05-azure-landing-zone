output "workspace_id" {
  description = "Log Analytics workspace ID."
  value       = azurerm_log_analytics_workspace.this.id
}

output "key_vault_id" {
  description = "Platform Key Vault ID."
  value       = azurerm_key_vault.this.id
}

output "diagnostic_target_keys" {
  description = "Keys of the external resources whose diagnostics go to the workspace."
  value       = sort(keys(var.diagnostic_targets))
}

output "detection_rule_ids" {
  description = "Sentinel scheduled rules created from rules.yaml."
  value       = sort(keys(azurerm_sentinel_alert_rule_scheduled.this))
}

output "unreferenced_queries" {
  description = "*.kql files no rule references (must be empty)."
  value       = local.unreferenced_queries
}

output "rules_without_tactics" {
  description = "Rules with no ATT&CK tactic (must be empty)."
  value       = local.rules_without_tactics
}
