output "enabled" {
  description = "Whether the firewall exists."
  value       = var.enable_firewall
}

output "private_ip" {
  description = "Firewall private IP (next hop for spokes), or null when disabled."
  value       = var.enable_firewall ? azurerm_firewall.this[0].ip_configuration[0].private_ip_address : null
}
