output "resource_group_name" {
  description = "Resource group of the state storage (backend.hcl resource_group_name)."
  value       = azurerm_resource_group.state.name
}

output "storage_account_name" {
  description = "State storage account (backend.hcl storage_account_name)."
  value       = azurerm_storage_account.state.name
}

output "container_name" {
  description = "State container (backend.hcl container_name)."
  value       = azurerm_storage_container.tfstate.name
}
