output "vnet_ids" {
  description = "VNet IDs keyed by VNet name (hub, spokes)."
  value       = { for k, v in azurerm_virtual_network.this : k => v.id }
}

output "subnet_ids" {
  description = "Subnet IDs keyed \"<vnet>/<subnet>\"."
  value       = { for k, s in azurerm_subnet.this : k => s.id }
}

output "nsg_ids" {
  description = "NSG IDs keyed by the \"<vnet>/<subnet>\" they protect."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}

output "storage_account_id" {
  description = "Workload storage account ID."
  value       = azurerm_storage_account.workload.id
}

output "private_dns_zone_ids" {
  description = "Private DNS zone IDs: blob (privatelink.blob.core.windows.net), vault (privatelink.vaultcore.azure.net)."
  value = {
    blob  = azurerm_private_dns_zone.blob.id
    vault = azurerm_private_dns_zone.vault.id
  }
}

output "private_endpoint_subnet_id" {
  description = "Subnet that hosts private endpoints."
  value       = azurerm_subnet.this[var.private_endpoint_subnet_key].id
}
