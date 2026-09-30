variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Management resource group."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant ID (Key Vault)."
  type        = string
}

variable "subscription_id" {
  description = "Subscription whose activity log is exported."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}

variable "retention_in_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 90
  validation {
    condition     = var.retention_in_days >= 30 && var.retention_in_days <= 730
    error_message = "retention_in_days must be 30-730."
  }
}

variable "key_vault_name" {
  description = "Globally unique name of the platform Key Vault."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "3-24 characters: letters, digits and hyphens, starting with a letter."
  }
}

variable "rules_file" {
  description = "Path to detections/rules.yaml."
  type        = string
}

variable "queries_dir" {
  description = "Directory holding the *.kql files referenced by rules_file."
  type        = string
}

variable "diagnostic_targets" {
  description = "Resources (key => ID and log category groups) whose diagnostics go to the workspace."
  type = map(object({
    resource_id     = string
    category_groups = list(string)
  }))
  default = {}
}

variable "enable_entra_diagnostics" {
  description = "Export Entra sign-in and audit logs (tenant setting; needs Entra ID P1/P2)."
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the Key Vault private endpoint (the vault has no public network access)."
  type        = string
}

variable "key_vault_private_dns_zone_id" {
  description = "privatelink.vaultcore.azure.net zone ID."
  type        = string
}
