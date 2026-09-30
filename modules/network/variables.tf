variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for VNets, NSGs and private DNS (connectivity)."
  type        = string
}

variable "workload_resource_group_name" {
  description = "Resource group for the workload storage account and its private endpoint."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
}

variable "vnets" {
  description = "VNets keyed by name; 'hub' is required, every other key is a spoke peered with it."
  type = map(object({
    address_space = list(string)
    subnets = map(object({
      address_prefixes = list(string)
    }))
  }))
  validation {
    condition     = contains(keys(var.vnets), "hub") && length(var.vnets) >= 2
    error_message = "vnets needs a 'hub' and at least one spoke."
  }
}

variable "nsg_rules" {
  description = "Extra NSG rules keyed by \"<vnet>/<subnet>\". Deny-all inbound (4096) is always added."
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

  validation {
    condition = alltrue([
      for r in flatten(values(var.nsg_rules)) : !(
        lower(r.direction) == "inbound" && lower(r.access) == "allow" &&
        contains(["*", "any", "internet", "0.0.0.0", "0.0.0.0/0", "::/0"], lower(r.source_address_prefix)) &&
        anytrue([
          for range in r.destination_port_ranges : anytrue([
            for port in [22, 3389, 5985, 5986] :
            range == "*" || try(
              port >= tonumber(split("-", range)[0]) &&
              port <= tonumber(split("-", range)[length(split("-", range)) - 1]),
              false
            )
          ])
        ])
      )
    ])
    error_message = "Management ports (22, 3389, 5985, 5986) must never be allowed inbound from the Internet/any source; use Bastion, a VPN or a jump host."
  }

  validation {
    condition = alltrue([
      for k in keys(var.nsg_rules) : contains(flatten([
        for vk, v in var.vnets : [
          for sk in keys(v.subnets) : "${vk}/${sk}"
          if !contains(["GatewaySubnet", "AzureFirewallSubnet", "AzureFirewallManagementSubnet"], sk)
        ]
      ]), k)
    ])
    error_message = "nsg_rules keys must be \"<vnet>/<subnet>\" of an existing subnet that has an NSG (not GatewaySubnet/AzureFirewall*)."
  }

  validation {
    condition     = alltrue([for rules in values(var.nsg_rules) : length(distinct([for r in rules : r.priority])) == length(rules)])
    error_message = "Priorities must be unique within one NSG."
  }

  validation {
    condition     = alltrue([for r in flatten(values(var.nsg_rules)) : r.priority >= 100 && r.priority <= 4000])
    error_message = "Priorities must be 100-4000 (4096 is the built-in deny-all)."
  }
}

variable "storage_account_name" {
  description = "Globally unique name of the workload storage account."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "3-24 lowercase letters and digits."
  }
}

variable "private_endpoint_subnet_key" {
  description = "Subnet (\"<vnet>/<subnet>\") that hosts private endpoints."
  type        = string
  default     = "internal/snet-private-endpoints"
  validation {
    condition = contains(flatten([
      for vk, v in var.vnets : [for sk in keys(v.subnets) : "${vk}/${sk}"]
    ]), var.private_endpoint_subnet_key)
    error_message = "private_endpoint_subnet_key must name an existing subnet as \"<vnet>/<subnet>\"."
  }
}
