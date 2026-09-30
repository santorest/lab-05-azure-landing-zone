variable "prefix" {
  description = "Short name prefix for every resource."
  type        = string
  default     = "corp"
}

variable "location" {
  description = "Azure region for the state storage."
  type        = string
  default     = "eastus2"
}

variable "subscription_id" {
  description = "Subscription that holds the Terraform state."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a GUID."
  }
}

variable "storage_account_name" {
  description = "Globally unique name of the state storage account."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "3-24 lowercase letters and digits."
  }
}

variable "deployer_ip" {
  description = "Single public IPv4 address allowed to reach the state account."
  type        = string
  validation {
    # try(): Terraform's && does not short-circuit, so a malformed value would otherwise raise an
    # evaluation error instead of this validation message.
    condition = try(can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.deployer_ip)) && !anytrue([
      for cidr in ["0.0.0.0/8", "10.0.0.0/8", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16"] :
      cidrhost(cidr, 0) == cidrhost("${var.deployer_ip}/${split("/", cidr)[1]}", 0)
    ]), false)
    error_message = "deployer_ip must be one public IPv4 address (no CIDR, no private/reserved range)."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}
