variable "prefix" {
  description = "Name of the root management group and prefix for its children."
  type        = string
  default     = "corp"
}

variable "location" {
  description = "Region for the managed identity of DeployIfNotExists assignments."
  type        = string
}

variable "subscription_id" {
  description = "Subscription governed by the budget (and optionally placed in the hierarchy)."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "subscription_placement" {
  description = "Management group key to place the subscription under (null: leave it where it is)."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.subscription_placement == null || contains(["platform", "landing-zones", "sandbox", "connectivity", "management", "identity", "online", "internal"], coalesce(var.subscription_placement, "-"))
    error_message = "subscription_placement must be one of the management group keys below corp."
  }
}

variable "allowed_locations" {
  description = "Regions where resources may be created."
  type        = list(string)
  validation {
    condition     = length(var.allowed_locations) > 0
    error_message = "allowed_locations cannot be empty (it would deny every deployment)."
  }
}

variable "required_tags" {
  description = "Tags every resource must carry."
  type        = list(string)
  default     = ["owner", "env", "cost-center"]
}

variable "log_analytics_workspace_id" {
  description = "Workspace that DeployIfNotExists diagnostics policies send logs to."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget for the subscription, in the billing currency."
  type        = number
  default     = 50
  validation {
    condition     = var.budget_amount > 0
    error_message = "budget_amount must be positive."
  }
}

variable "budget_start_date" {
  description = "First month of the budget, as YYYY-MM-01T00:00:00Z."
  type        = string
  validation {
    condition     = can(regex("^\\d{4}-(0[1-9]|1[0-2])-01T00:00:00Z$", var.budget_start_date))
    error_message = "Azure budgets must start on the first day of a month: YYYY-MM-01T00:00:00Z."
  }
}

variable "budget_thresholds" {
  description = "Percentages of the budget that trigger an alert."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "budget_contact_emails" {
  description = "Who receives budget alerts."
  type        = list(string)
  validation {
    condition     = length(var.budget_contact_emails) > 0
    error_message = "At least one budget contact is required."
  }
}
