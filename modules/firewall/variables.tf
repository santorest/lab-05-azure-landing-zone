variable "enable_firewall" {
  description = "Create Azure Firewall (Basic) and route spoke traffic through it. Off by default: NSGs are the enforced design."
  type        = bool
  default     = false
}

variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Connectivity resource group."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}

variable "firewall_subnet_id" {
  description = "ID of the hub's AzureFirewallSubnet (required when enabled)."
  type        = string
  default     = null
  validation {
    condition     = !var.enable_firewall || var.firewall_subnet_id != null
    error_message = "firewall_subnet_id is required when enable_firewall = true."
  }
}

variable "firewall_management_subnet_id" {
  description = "ID of the hub's AzureFirewallManagementSubnet (Basic SKU needs it; required when enabled)."
  type        = string
  default     = null
  validation {
    condition     = !var.enable_firewall || var.firewall_management_subnet_id != null
    error_message = "firewall_management_subnet_id is required when enable_firewall = true."
  }
}

variable "route_subnet_ids" {
  description = "Spoke subnets (key => subnet ID) whose default route goes through the firewall."
  type        = map(string)
  default     = {}
}
