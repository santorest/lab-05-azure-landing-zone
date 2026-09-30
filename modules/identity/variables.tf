variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "subscription_id" {
  description = "Subscription where Owner/User Access Administrator are PIM-eligible."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "break_glass_group_id" {
  description = "Object ID of the emergency-access group excluded from every CA policy. Managed outside Terraform on purpose."
  type        = string
  default     = null
  validation {
    condition     = var.break_glass_group_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", coalesce(var.break_glass_group_id, "-")))
    error_message = "break_glass_group_id must be null or the group's object ID (a GUID)."
  }
}

variable "ca_state" {
  description = "State of every Conditional Access policy. Stay report-only until sign-in logs show no surprises."
  type        = string
  default     = "enabledForReportingButNotEnforced"
  validation {
    condition     = contains(["enabledForReportingButNotEnforced", "enabled", "disabled"], var.ca_state)
    error_message = "ca_state must be enabledForReportingButNotEnforced, enabled or disabled."
  }
  validation {
    condition     = var.ca_state != "enabled" || trimspace(coalesce(var.break_glass_group_id, " ")) != ""
    error_message = "Enforcing Conditional Access requires break_glass_group_id (an excluded emergency-access group), or you can lock every admin out."
  }
}

variable "pim_eligibility_days" {
  description = "How long a PIM eligibility lasts before it must be renewed."
  type        = number
  default     = 365
  validation {
    condition     = var.pim_eligibility_days >= 1 && var.pim_eligibility_days <= 365
    error_message = "pim_eligibility_days must be 1-365."
  }
}
