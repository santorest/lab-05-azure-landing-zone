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

output "private_dns_zone_id" {
  description = "privatelink.blob.core.windows.net zone ID."
  value       = azurerm_private_dns_zone.blob.id
}
