variable "prefix" {
  description = "Name prefix for every resource and the root management group."
  type        = string
  default     = "corp"
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus2"
  validation {
    condition     = contains(var.allowed_locations, var.location)
    error_message = "location must be one of allowed_locations, or the landing zone's own policy would deny its later updates."
  }
}

variable "subscription_id" {
  description = "Landing-zone subscription."
  type        = string
}

variable "tenant_id" {
  description = "Entra tenant."
  type        = string
}

variable "tags" {
  description = "Tags on every resource; owner, env and cost-center are required."
  type        = map(string)
  validation {
    condition     = alltrue([for t in ["owner", "env", "cost-center"] : length(trimspace(lookup(var.tags, t, ""))) > 0])
    error_message = "tags must include non-empty owner, env and cost-center."
  }
}

variable "allowed_locations" {
  description = "Regions where resources may be created (Azure Policy)."
  type        = list(string)
  default     = ["eastus2"]
}

variable "subscription_placement" {
  description = "Management group key the subscription is placed under."
  type        = string
  default     = "online"
}

variable "enable_firewall" {
  description = "Add Azure Firewall Basic in the hub (≈ +$10/day estimated). NSGs are the default design."
  type        = bool
  default     = false
}

variable "storage_account_name" {
  description = "Globally unique name of the workload storage account."
  type        = string
}

variable "key_vault_name" {
  description = "Globally unique name of the platform Key Vault."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget in the billing currency."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "First month of the budget (YYYY-MM-01T00:00:00Z)."
  type        = string
}

variable "budget_contact_emails" {
  description = "Budget alert recipients."
  type        = list(string)
}

variable "ca_state" {
  description = "Conditional Access state (report-only by default)."
  type        = string
  default     = "enabledForReportingButNotEnforced"
}

variable "break_glass_group_id" {
  description = "Emergency-access group excluded from Conditional Access (required to enforce CA)."
  type        = string
  default     = null
}

variable "nsg_rules" {
  description = "Extra NSG rules keyed \"<vnet>/<subnet>\" (see modules/network)."
  type = map(list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_address_prefix      = string
    destination_address_prefix = string
    destination_port_ranges    = list(string)
  })))
  default = {}
}
